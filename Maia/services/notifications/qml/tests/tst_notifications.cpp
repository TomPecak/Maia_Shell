// Maia.Notifications and Maia.Notifications.Center against the real service (without D-Bus): a
// program sends with Notification, a shell sees it in NotificationsModel and NotificationPopupsModel and
// acts on it with NotificationCenter.
//
// The service runs with its own sockets and its own display name, so that neither its sockets nor
// its image directory are those of the session the test runs in.

#include "Notification.h"
#include "NotificationCenter.h"
#include "NotificationPopupsModel.h"
#include "NotificationRoles.h"
#include "Notifications.h"
#include "NotificationsModel.h"

#include <QDir>
#include <QElapsedTimer>
#include <QProcess>
#include <QSignalSpy>
#include <QTest>
#include <QTimer>

#include <memory>
#include <vector>

using namespace MaiaNotifications;

namespace {

QString runtimeDir()
{
    const QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath());
    return dir + QStringLiteral("/maia");
}

QVariant role(const QAbstractItemModel &model, int row, int role)
{
    return model.data(model.index(row, 0), role);
}

QVariantMap action(const QString &key, const QString &label)
{
    return {{QStringLiteral("key"), key}, {QStringLiteral("label"), label}};
}

} // namespace

class TestNotifications : public QObject
{
    Q_OBJECT

private:
    QProcess m_service;
    QString m_display;

    void startService()
    {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("MAIA_NOTIFICATIONS_DBUS"), QStringLiteral("0"));
        env.insert(QStringLiteral("WAYLAND_DISPLAY"), m_display);
        env.insert(QStringLiteral("MAIA_NOTIFICATIONS_SOCKET"), qEnvironmentVariable("MAIA_NOTIFICATIONS_SOCKET"));
        env.insert(QStringLiteral("MAIA_NOTIFICATIONS_CENTER_SOCKET"), qEnvironmentVariable("MAIA_NOTIFICATIONS_CENTER_SOCKET"));
        m_service.setProcessEnvironment(env);
        m_service.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        m_service.start(QStringLiteral(MAIA_NOTIFICATIONS_SERVICE), {});
        QVERIFY(m_service.waitForStarted());
    }

    void stopService()
    {
        m_service.terminate();
        if (!m_service.waitForFinished(3000))
            m_service.kill();
    }

    // A program's notification, sent
    std::unique_ptr<Notification> sent(const QString &summary, int timeout = -1)
    {
        auto n = std::make_unique<Notification>();
        n->setSummary(summary);
        n->setTimeout(timeout);
        n->send();
        return n;
    }

private Q_SLOTS:
    void initTestCase()
    {
        // Short names: a Unix socket path has at most 107 bytes
        m_display = QStringLiteral("maia-tst-%1").arg(QCoreApplication::applicationPid());
        qputenv("MAIA_NOTIFICATIONS_SOCKET", (runtimeDir() + QStringLiteral("/tn-%1.sock").arg(QCoreApplication::applicationPid())).toUtf8());
        qputenv("MAIA_NOTIFICATIONS_CENTER_SOCKET",
                (runtimeDir() + QStringLiteral("/tnc-%1.sock").arg(QCoreApplication::applicationPid())).toUtf8());
        startService();
        Notifications notifications;
        NotificationCenter center;
        QTRY_VERIFY_WITH_TIMEOUT(notifications.available(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(center.connected(), 5000);
    }

    void cleanupTestCase()
    {
        stopService();
    }

    void init()
    {
        // A clean list for every test. Only what is needed, and confirmed by the service: the shell's
        // requests and the program's notifications go over two connections, a "clear all" still on
        // its way would also clear the next test's notification
        NotificationCenter center;
        if (center.doNotDisturb()) {
            center.setDoNotDisturb(false);
            QTRY_VERIFY(!center.doNotDisturbActive());
        }
        if (center.count() > 0) {
            center.dismissAll();
            // "Clear all" keeps critical notifications: those one by one
            QTest::qWait(50);
            NotificationsModel model;
            for (int row = 0; row < model.rowCount(); ++row)
                center.dismiss(role(model, row, NotificationRoles::NotificationIdRole).toUInt());
            QTRY_COMPARE(center.count(), 0);
        }
    }

    void aSentNotificationReachesTheListAndThePopups()
    {
        NotificationsModel model;
        NotificationPopupsModel popups;
        auto n = std::make_unique<Notification>();
        n->setAppName(QStringLiteral("Backup"));
        n->setDesktopEntry(QStringLiteral("org.maia.backup"));
        n->setIconName(QStringLiteral("drive-harddisk"));
        n->setSummary(QStringLiteral("Backup finished"));
        n->setBody(QStringLiteral("<b>120</b> files & folders"));
        n->setActions({action(QStringLiteral("default"), QString()), action(QStringLiteral("open"), QStringLiteral("Open"))});
        QVERIFY(!n->isActive());
        n->send();
        QVERIFY(n->isActive());
        QTRY_VERIFY(n->notificationId() != 0);

        QTRY_COMPARE(model.rowCount(), 1);
        QCOMPARE(role(model, 0, NotificationRoles::NotificationIdRole).toUInt(), n->notificationId());
        QCOMPARE(role(model, 0, NotificationRoles::AppNameRole).toString(), QStringLiteral("Backup"));
        QCOMPARE(role(model, 0, NotificationRoles::SummaryRole).toString(), QStringLiteral("Backup finished"));
        QCOMPARE(role(model, 0, NotificationRoles::BodyRole).toString(), QStringLiteral("<b>120</b> files &amp; folders"));
        QVERIFY(role(model, 0, NotificationRoles::HasDefaultActionRole).toBool());
        // "default" is the click on the notification, not a button
        const QVariantList actions = role(model, 0, NotificationRoles::ActionsRole).toList();
        QCOMPARE(actions.size(), 1);
        QCOMPARE(actions.first().toMap().value(QStringLiteral("label")).toString(), QStringLiteral("Open"));
        QTRY_COMPARE(popups.rowCount(), 1);
        QCOMPARE(role(popups, 0, NotificationRoles::NotificationIdRole).toUInt(), n->notificationId());
    }

    void aPopupEndsByItselfAndTheNotificationStays()
    {
        NotificationsModel model;
        NotificationPopupsModel popups;
        auto n = sent(QStringLiteral("Short"), 1000);
        QTRY_COMPARE(popups.rowCount(), 1);
        QElapsedTimer shown;
        shown.start();
        QTRY_COMPARE_WITH_TIMEOUT(popups.rowCount(), 0, 3000);
        QVERIFY2(shown.elapsed() >= 900, qPrintable(QString::number(shown.elapsed())));
        // Expired, still in the list, still active for its sender
        QTRY_VERIFY(role(model, 0, NotificationRoles::ExpiredRole).toBool());
        QCOMPARE(model.rowCount(), 1);
        QVERIFY(n->isActive());
    }

    void pausedPopupsWaitAndThenGoOn()
    {
        NotificationPopupsModel popups;
        auto n = sent(QStringLiteral("Hovered"), 1000);
        QTRY_COMPARE(popups.rowCount(), 1);
        popups.setPaused(true);
        QTest::qWait(1500);
        QCOMPARE(popups.rowCount(), 1);
        popups.setPaused(false);
        QTRY_COMPARE_WITH_TIMEOUT(popups.rowCount(), 0, 3000);
    }

    void criticalAndTimeoutZeroStayUntilClosed()
    {
        NotificationPopupsModel popups;
        popups.setDefaultTimeout(1000);
        auto critical = std::make_unique<Notification>();
        critical->setSummary(QStringLiteral("Battery empty"));
        critical->setUrgency(Notification::Critical);
        critical->send();
        auto sticky = sent(QStringLiteral("Until closed"), 0);
        auto normal = sent(QStringLiteral("Normal"));
        QTRY_COMPARE(popups.rowCount(), 3);
        QTRY_COMPARE_WITH_TIMEOUT(popups.rowCount(), 2, 3000);
        QTest::qWait(500);
        QCOMPARE(popups.rowCount(), 2);
        // Hidden by hand, it goes
        popups.hide(role(popups, 0, NotificationRoles::NotificationIdRole).toUInt());
        QCOMPARE(popups.rowCount(), 1);
    }

    void popupsBeyondTheMaximumWaitForAPlace()
    {
        NotificationPopupsModel popups;
        popups.setMaximumCount(2);
        std::vector<std::unique_ptr<Notification>> list;
        for (int i = 0; i < 5; ++i)
            list.push_back(sent(QStringLiteral("n%1").arg(i), 0));
        QTRY_COMPARE(popups.rowCount() + popups.waiting(), 5);
        QCOMPARE(popups.rowCount(), 2);
        // The oldest first
        QCOMPARE(role(popups, 0, NotificationRoles::SummaryRole).toString(), QStringLiteral("n0"));
        popups.hide(role(popups, 0, NotificationRoles::NotificationIdRole).toUInt());
        QCOMPARE(popups.rowCount(), 2);
        QCOMPARE(popups.waiting(), 2);
        QCOMPARE(role(popups, 1, NotificationRoles::SummaryRole).toString(), QStringLiteral("n2"));
    }

    void criticalNotificationsWaitInFrontOfTheOthers()
    {
        NotificationPopupsModel popups;
        popups.setMaximumCount(1);
        auto first = sent(QStringLiteral("first"), 0);
        QTRY_COMPARE(popups.rowCount(), 1);
        auto second = sent(QStringLiteral("second"), 0);
        auto critical = std::make_unique<Notification>();
        critical->setSummary(QStringLiteral("Battery empty"));
        critical->setUrgency(Notification::Critical);
        critical->send();
        QTRY_COMPARE(popups.waiting(), 2);
        popups.hide(role(popups, 0, NotificationRoles::NotificationIdRole).toUInt());
        QCOMPARE(role(popups, 0, NotificationRoles::SummaryRole).toString(), QStringLiteral("Battery empty"));
    }

    void anActionReachesTheSenderAndClosesIt()
    {
        NotificationsModel model;
        NotificationCenter center;
        auto n = std::make_unique<Notification>();
        n->setSummary(QStringLiteral("Update ready"));
        n->setActions({action(QStringLiteral("restart"), QStringLiteral("Restart"))});
        QSignalSpy invoked(n.get(), &Notification::actionInvoked);
        QSignalSpy closed(n.get(), &Notification::closed);
        n->send();
        QTRY_COMPARE(model.rowCount(), 1);
        const uint id = role(model, 0, NotificationRoles::NotificationIdRole).toUInt();
        center.invokeAction(id, QStringLiteral("unknown"));
        center.invokeAction(id, QStringLiteral("restart"));
        QTRY_COMPARE(invoked.count(), 1);
        QCOMPARE(invoked.first().first().toString(), QStringLiteral("restart"));
        QTRY_COMPARE(closed.count(), 1);
        QCOMPARE(closed.first().first().value<Notification::CloseReason>(), Notification::Dismissed);
        QVERIFY(!n->isActive());
        QTRY_COMPARE(model.rowCount(), 0);
    }

    void aReplyReachesTheSender()
    {
        NotificationsModel model;
        NotificationCenter center;
        auto n = std::make_unique<Notification>();
        n->setSummary(QStringLiteral("Anna"));
        n->setInlineReply(true);
        n->setReplyPlaceholder(QStringLiteral("Reply to Anna…"));
        QSignalSpy replied(n.get(), &Notification::replied);
        n->send();
        QTRY_COMPARE(model.rowCount(), 1);
        QVERIFY(role(model, 0, NotificationRoles::InlineReplyRole).toBool());
        QCOMPARE(role(model, 0, NotificationRoles::ReplyPlaceholderRole).toString(), QStringLiteral("Reply to Anna…"));
        center.reply(role(model, 0, NotificationRoles::NotificationIdRole).toUInt(), QStringLiteral("On my way"));
        QTRY_COMPARE(replied.count(), 1);
        QCOMPARE(replied.first().first().toString(), QStringLiteral("On my way"));
    }

    void theSenderClosesAndUpdates()
    {
        NotificationsModel model;
        auto older = sent(QStringLiteral("Copying 1 of 10"));
        auto newer = sent(QStringLiteral("Other"));
        QTRY_COMPARE(model.rowCount(), 2);
        QCOMPARE(role(model, 0, NotificationRoles::SummaryRole).toString(), QStringLiteral("Other"));
        const uint id = older->notificationId();
        QVERIFY(id != 0);

        QTest::qWait(5); // a later time than the other one
        older->setSummary(QStringLiteral("Copying 9 of 10"));
        older->send();
        // The same notification, replaced: to the top
        QTRY_COMPARE(role(model, 0, NotificationRoles::SummaryRole).toString(), QStringLiteral("Copying 9 of 10"));
        QCOMPARE(role(model, 0, NotificationRoles::NotificationIdRole).toUInt(), id);
        QCOMPARE(model.rowCount(), 2);

        QSignalSpy closed(older.get(), &Notification::closed);
        older->close();
        QTRY_COMPARE(model.rowCount(), 1);
        QTRY_COMPARE(closed.count(), 1);
        QCOMPARE(closed.first().first().value<Notification::CloseReason>(), Notification::ClosedByApp);
    }

    void aDestroyedObjectLeavesItsNotification()
    {
        NotificationsModel model;
        {
            auto n = sent(QStringLiteral("Outlives its object"));
            QTRY_COMPARE(model.rowCount(), 1);
        }
        QTest::qWait(100);
        QCOMPARE(model.rowCount(), 1);
    }

    void doNotDisturbKeepsPopupsAwayButNotCriticalOnes()
    {
        NotificationCenter center;
        NotificationsModel model;
        NotificationPopupsModel popups;
        QSignalSpy changed(&center, &NotificationCenter::doNotDisturbChanged);
        center.setDoNotDisturb(true);
        QTRY_VERIFY(center.doNotDisturb() && center.doNotDisturbActive());
        QVERIFY(!center.doNotDisturbUntil().isValid());
        auto quiet = sent(QStringLiteral("Quiet"));
        auto critical = std::make_unique<Notification>();
        critical->setSummary(QStringLiteral("Battery empty"));
        critical->setUrgency(Notification::Critical);
        critical->send();
        QTRY_COMPARE(model.rowCount(), 2);
        QTRY_COMPARE(popups.rowCount(), 1);
        QCOMPARE(role(popups, 0, NotificationRoles::SummaryRole).toString(), QStringLiteral("Battery empty"));

        center.setDoNotDisturbFor(30);
        QTRY_VERIFY(center.doNotDisturbUntil().isValid());
        const qint64 left = QDateTime::currentDateTime().msecsTo(center.doNotDisturbUntil());
        QVERIFY(left > 29 * 60 * 1000 && left <= 30 * 60 * 1000);
        center.setDoNotDisturb(false);
        QTRY_VERIFY(!center.doNotDisturbActive());
    }

    void aFloodKeepsTheGuiThreadFree()
    {
        NotificationsModel model;
        NotificationPopupsModel popups;
        constexpr int kCount = 1000;
        std::vector<std::unique_ptr<Notification>> list;
        list.reserve(kCount);
        for (int i = 0; i < kCount; ++i) {
            auto n = std::make_unique<Notification>();
            n->setSummary(QStringLiteral("Flood %1").arg(i));
            n->setBody(QStringLiteral("A message with <b>markup</b> number %1").arg(i));
            list.push_back(std::move(n));
        }

        // The GUI thread's longest stall while the flood comes back: a 1 ms timer measures it. The
        // wait is a plain event loop (QTRY_* would sleep 10 ms between its checks)
        qint64 longest = 0;
        QElapsedTimer total;
        total.start();
        for (auto &n : list)
            n->send();
        const qint64 sending = total.elapsed();
        QElapsedTimer sinceTick;
        sinceTick.start();
        QTimer ticker;
        ticker.setTimerType(Qt::PreciseTimer);
        ticker.setInterval(1);
        QEventLoop loop;
        const QString last = QStringLiteral("Flood %1").arg(kCount - 1);
        connect(&ticker, &QTimer::timeout, this, [&] {
            longest = std::max(longest, sinceTick.restart());
            if (model.rowCount() == 200 && role(model, 0, NotificationRoles::SummaryRole).toString() == last)
                loop.quit();
        });
        QTimer::singleShot(10000, &loop, &QEventLoop::quit);
        ticker.start();
        loop.exec();
        ticker.stop();
        QCOMPARE(model.rowCount(), 200);
        QCOMPARE(role(model, 0, NotificationRoles::SummaryRole).toString(), last);
        qInfo() << kCount << "notifications: sent in" << sending << "ms, all shown after" << total.elapsed() << "ms, longest stall of the GUI thread"
                << longest << "ms";
        // Half a frame at 60 Hz, in a debug build
        QVERIFY2(longest < 8, qPrintable(QStringLiteral("%1 ms").arg(longest)));
        QVERIFY(popups.rowCount() <= popups.maximumCount());
    }

    void aRestartedServiceIsFoundAgainAndWaitingNotificationsGoOut()
    {
        Notifications notifications;
        NotificationCenter center;
        NotificationsModel model;
        auto before = sent(QStringLiteral("Before"));
        QTRY_COMPARE(model.rowCount(), 1);
        QSignalSpy closed(before.get(), &Notification::closed);

        stopService();
        QTRY_VERIFY_WITH_TIMEOUT(!center.connected(), 5000);
        QTRY_VERIFY(!notifications.available());
        // The shell keeps what it had; the sender's notification is gone with the service
        QCOMPARE(model.rowCount(), 1);
        QTRY_COMPARE(closed.count(), 1);
        QCOMPARE(closed.first().first().value<Notification::CloseReason>(), Notification::Other);

        auto waiting = sent(QStringLiteral("Sent without the service"));
        QVERIFY(waiting->isActive());
        startService();
        QTRY_VERIFY_WITH_TIMEOUT(center.connected() && notifications.available(), 5000);
        QTRY_COMPARE(model.rowCount(), 1);
        QTRY_COMPARE(role(model, 0, NotificationRoles::SummaryRole).toString(), QStringLiteral("Sent without the service"));
        QTRY_VERIFY(waiting->notificationId() != 0);
    }
};

QTEST_MAIN(TestNotifications)
#include "tst_notifications.moc"
