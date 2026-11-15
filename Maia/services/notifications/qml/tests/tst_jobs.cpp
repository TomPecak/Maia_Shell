// JobsModel and the job commands of NotificationCenter against the real service on a private
// dbus-daemon; a client written with QtDBus does what KJobWidgets does for KIO in Dolphin.

#include "JobsModel.h"
#include "NotificationCenter.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDir>
#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace MaiaNotifications;

namespace {

QVariant role(const QAbstractItemModel &model, int row, int role)
{
    return model.data(model.index(row, 0), role);
}

} // namespace

// Counts the requests a job's application gets
class Requests : public QObject
{
    Q_OBJECT

public:
    int cancel = 0;
    int suspend = 0;

public Q_SLOTS:
    void onCancel() { ++cancel; }
    void onSuspend() { ++suspend; }
};

class TestJobs : public QObject
{
    Q_OBJECT

private:
    QProcess m_bus;
    QTemporaryDir m_settingsDir;
    QProcess m_service;
    QDBusConnection m_client{QStringLiteral("none")};

    // requestView of JobViewServerV2, as KJobWidgets calls it
    QString requestView(const QVariantMap &hints)
    {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.JobViewServer"), QStringLiteral("/JobViewServer"),
                                                           QStringLiteral("org.kde.JobViewServerV2"), QStringLiteral("requestView"));
        call << QStringLiteral("org.kde.dolphin") << 3 << hints;
        QDBusReply<QDBusObjectPath> reply = m_client.call(call);
        return reply.isValid() ? reply.value().path() : QString();
    }

    void callJob(const QString &path, const QString &method, const QVariantList &arguments)
    {
        QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.JobViewServer"), path, QStringLiteral("org.kde.JobViewV3"), method);
        call.setArguments(arguments);
        QVERIFY(m_client.call(call).type() == QDBusMessage::ReplyMessage);
    }

private Q_SLOTS:
    void initTestCase()
    {
        m_bus.start(QStringLiteral("dbus-daemon"), {QStringLiteral("--session"), QStringLiteral("--nofork"), QStringLiteral("--print-address=1")});
        QVERIFY(m_bus.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(m_bus.readLine()).trimmed();
        m_client = QDBusConnection::connectToBus(address, QStringLiteral("jobs-client"));
        QVERIFY(m_client.isConnected());

        const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath()) + QStringLiteral("/maia");
        const QString pid = QString::number(QCoreApplication::applicationPid());
        qputenv("MAIA_NOTIFICATIONS_CENTER_SOCKET", (runtime + QStringLiteral("/tjc-") + pid + QStringLiteral(".sock")).toUtf8());
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("DBUS_SESSION_BUS_ADDRESS"), address);
        env.insert(QStringLiteral("MAIA_NOTIFICATIONS_JOBS"), QStringLiteral("1"));
        env.insert(QStringLiteral("WAYLAND_DISPLAY"), QStringLiteral("maia-tstj-") + pid);
        env.insert(QStringLiteral("MAIA_NOTIFICATIONS_SOCKET"), runtime + QStringLiteral("/tjn-") + pid + QStringLiteral(".sock"));
        env.insert(QStringLiteral("MAIA_NOTIFICATIONS_CENTER_SOCKET"), qEnvironmentVariable("MAIA_NOTIFICATIONS_CENTER_SOCKET"));
        // Its own settings file: never the user's
        env.insert(QStringLiteral("MAIA_NOTIFICATIONS_SETTINGS"), m_settingsDir.filePath(QStringLiteral("maia-notifications-service.json")));
        m_service.setProcessEnvironment(env);
        m_service.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        m_service.start(QStringLiteral(MAIA_NOTIFICATIONS_SERVICE), {});
        QVERIFY(m_service.waitForStarted());
        NotificationCenter center;
        QTRY_VERIFY_WITH_TIMEOUT(center.connected(), 5000);
        // The job server's name is on the bus
        QTRY_VERIFY_WITH_TIMEOUT(m_client.interface()->isServiceRegistered(QStringLiteral("org.kde.JobViewServer")), 5000);
    }

    void cleanupTestCase()
    {
        m_service.terminate();
        m_service.waitForFinished(3000);
        m_bus.kill();
        m_bus.waitForFinished(3000);
    }

    void aCopyFromStartToEnd()
    {
        JobsModel all;
        JobsModel running;
        running.setRunningOnly(true);
        const QString path = requestView({{QStringLiteral("title"), QStringLiteral("Copying")}, {QStringLiteral("immediate"), true}});
        QVERIFY(path.startsWith(QStringLiteral("/org/kde/notificationmanager/jobs/JobView_")));
        QTRY_COMPARE(all.rowCount(), 1);
        QCOMPARE(running.rowCount(), 1);
        QCOMPARE(role(all, 0, JobsModel::TitleRole).toString(), QStringLiteral("Copying"));
        QCOMPARE(role(all, 0, JobsModel::DesktopEntryRole).toString(), QStringLiteral("org.kde.dolphin"));
        QCOMPARE(role(all, 0, JobsModel::StateRole).toInt(), int(NotificationCenter::JobRunning));
        QVERIFY(role(all, 0, JobsModel::KillableRole).toBool() && role(all, 0, JobsModel::SuspendableRole).toBool());

        callJob(path, QStringLiteral("update"),
                {QVariantMap{{QStringLiteral("percent"), 50u},
                             {QStringLiteral("processedBytes"), QVariant::fromValue<qulonglong>(500)},
                             {QStringLiteral("totalBytes"), QVariant::fromValue<qulonglong>(1000)},
                             {QStringLiteral("descriptionLabel1"), QStringLiteral("Destination")},
                             {QStringLiteral("descriptionValue1"), QStringLiteral("/media/usb")},
                             {QStringLiteral("destUrl"), QStringLiteral("file:///media/usb")}}});
        QTRY_COMPARE(role(all, 0, JobsModel::PercentRole).toInt(), 50);
        QCOMPARE(all.runningCount(), 1);
        QCOMPARE(all.percent(), 50);
        QCOMPARE(role(all, 0, JobsModel::TotalBytesRole).toDouble(), 1000.0);
        QCOMPARE(role(all, 0, JobsModel::DestinationRole).toString(), QStringLiteral("file:///media/usb"));
        QCOMPARE(role(all, 0, JobsModel::FieldsRole).toList().size(), 1);

        callJob(path, QStringLiteral("terminate"), {0u, QString(), QVariantMap()});
        QTRY_COMPARE(role(all, 0, JobsModel::StateRole).toInt(), int(NotificationCenter::JobFinished));
        // A running-only model lets it go, the whole list keeps it until dismissed
        QTRY_COMPARE(running.rowCount(), 0);
        QCOMPARE(all.runningCount(), 0);
        QCOMPARE(all.percent(), -1);
        NotificationCenter center;
        center.dismissJob(role(all, 0, JobsModel::JobIdRole).toUInt());
        QTRY_COMPARE(all.rowCount(), 0);
    }

    void cancelAndPauseReachTheApplication()
    {
        JobsModel all;
        const QString path = requestView({{QStringLiteral("title"), QStringLiteral("Copying")}, {QStringLiteral("immediate"), true}});
        Requests requests;
        QVERIFY(m_client.connect(QString(), path, QStringLiteral("org.kde.JobViewV3"), QStringLiteral("cancelRequested"), &requests, SLOT(onCancel())));
        QVERIFY(m_client.connect(QString(), path, QStringLiteral("org.kde.JobViewV3"), QStringLiteral("suspendRequested"), &requests, SLOT(onSuspend())));
        QTRY_COMPARE(all.rowCount(), 1);
        const uint id = role(all, 0, JobsModel::JobIdRole).toUInt();
        NotificationCenter center;
        center.suspendJob(id, true);
        QTRY_COMPARE(requests.suspend, 1);
        center.cancelJob(id);
        QTRY_COMPARE(requests.cancel, 1);
        // The application ends it as canceled: it goes without a trace
        callJob(path, QStringLiteral("terminate"), {1u, QStringLiteral("Canceled"), QVariantMap()});
        QTRY_COMPARE(all.rowCount(), 0);
    }

    void severalJobsMakeOneProgress()
    {
        JobsModel all;
        const QString big = requestView({{QStringLiteral("title"), QStringLiteral("Copying")}, {QStringLiteral("immediate"), true}});
        const QString small = requestView({{QStringLiteral("title"), QStringLiteral("Copying")}, {QStringLiteral("immediate"), true}});
        QTRY_COMPARE(all.rowCount(), 2);
        callJob(big, QStringLiteral("update"), {QVariantMap{{QStringLiteral("processedBytes"), QVariant::fromValue<qulonglong>(100)}, {QStringLiteral("totalBytes"), QVariant::fromValue<qulonglong>(900)}}});
        callJob(small, QStringLiteral("update"), {QVariantMap{{QStringLiteral("processedBytes"), QVariant::fromValue<qulonglong>(100)}, {QStringLiteral("totalBytes"), QVariant::fromValue<qulonglong>(100)}}});
        // By bytes: 200 of 1000
        QTRY_COMPARE(all.percent(), 20);
        QCOMPARE(all.runningCount(), 2);
        callJob(big, QStringLiteral("terminate"), {1u, QString(), QVariantMap()});
        callJob(small, QStringLiteral("terminate"), {1u, QString(), QVariantMap()});
        QTRY_COMPARE(all.rowCount(), 0);
    }
};

QTEST_MAIN(TestJobs)
#include "tst_jobs.moc"
