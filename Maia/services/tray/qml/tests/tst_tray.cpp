// Maia.Tray against the real tray service on a private D-Bus session bus, with
// tools/fake-tray-item.py as the application (an item and a menu over D-Bus, as
// KStatusNotifierItem shows them).

#include "Tray.h"
#include "TrayItemsModel.h"
#include "TrayMenu.h"

#include <QFileInfo>
#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using namespace MaiaTray;

namespace {

// The environment of the processes of the test: nothing of a Maia session around it (MAIA_LOG_FILE
// would truncate the user's log), its own bus and runtime directory
QProcessEnvironment cleanEnvironment(const QString &bus, const QString &runtime)
{
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    for (const QString &name : environment.keys()) {
        if (name.startsWith(QLatin1String("MAIA_")))
            environment.remove(name);
    }
    environment.insert(QStringLiteral("DBUS_SESSION_BUS_ADDRESS"), bus);
    environment.insert(QStringLiteral("XDG_RUNTIME_DIR"), runtime);
    environment.insert(QStringLiteral("WAYLAND_DISPLAY"), QStringLiteral("tst-tray"));
    environment.insert(QStringLiteral("MAIA_TRAY_SOCKET"), runtime + QStringLiteral("/tray.sock"));
    return environment;
}

// An application with an item; what the tray does to it is in its output
class FakeApp
{
public:
    FakeApp(const QProcessEnvironment &environment, const QStringList &arguments)
    {
        m_process.setProcessEnvironment(environment);
        m_process.setProcessChannelMode(QProcess::ForwardedErrorChannel);
        m_process.start(QStringLiteral("python3"), QStringList{QStringLiteral(MAIA_FAKE_TRAY_ITEM)} + arguments);
        QObject::connect(&m_process, &QProcess::readyReadStandardOutput, [this] {
            while (m_process.canReadLine())
                m_lines.append(QString::fromUtf8(m_process.readLine()).trimmed());
        });
    }

    ~FakeApp()
    {
        m_process.kill();
        m_process.waitForFinished(2000);
    }

    void send(const QString &command)
    {
        m_process.write((command + QLatin1Char('\n')).toUtf8());
    }

    bool waitFor(const QString &line, int timeout = 5000)
    {
        QDeadlineTimer deadline(timeout);
        while (!m_lines.contains(line)) {
            if (deadline.hasExpired())
                return false;
            QTest::qWait(5);
        }
        return true;
    }

    const QStringList &lines() const { return m_lines; }

private:
    QProcess m_process;
    QStringList m_lines;
};

} // namespace

class TestTray : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void cleanupTestCase();
    void cleanup();
    void selectionPutsAttentionFirst();
    void itemsAppearWithTheirData();
    void statusMovesItemsBetweenFilters();
    void clicksReachTheApplication();
    void menusFollowTheApplication();
    void pixelsBecomeFiles();
    void itemsGoWithTheirApplication();

private:
    QTemporaryDir m_dir;
    QProcess m_bus;
    QProcess m_service;
    QProcessEnvironment m_environment;
};

void TestTray::initTestCase()
{
    QVERIFY(m_dir.isValid());
    m_bus.start(QStringLiteral("dbus-daemon"), {QStringLiteral("--session"), QStringLiteral("--nofork"), QStringLiteral("--print-address=1")});
    QVERIFY(m_bus.waitForReadyRead(5000));
    const QString address = QString::fromUtf8(m_bus.readLine()).trimmed();
    QVERIFY(!address.isEmpty());

    m_environment = cleanEnvironment(address, m_dir.path());
    m_service.setProcessEnvironment(m_environment);
    m_service.setProcessChannelMode(QProcess::ForwardedErrorChannel);
    m_service.start(QStringLiteral(MAIA_TRAY_SERVICE), {});
    QVERIFY(m_service.waitForStarted());
    const QString socket = m_environment.value(QStringLiteral("MAIA_TRAY_SOCKET"));
    QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(socket), 5000);

    // The module's connection reads its socket from here when it is first used
    qputenv("MAIA_TRAY_SOCKET", socket.toUtf8());
    Tray tray;
    QTRY_VERIFY_WITH_TIMEOUT(tray.connected(), 5000);
}

void TestTray::cleanupTestCase()
{
    m_service.terminate();
    m_service.waitForFinished(5000);
    m_bus.kill();
    m_bus.waitForFinished(2000);
}

// The application of a test is gone before the next one starts
void TestTray::cleanup()
{
    Tray tray;
    QTRY_COMPARE_WITH_TIMEOUT(tray.count(), 0, 5000);
}

void TestTray::selectionPutsAttentionFirst()
{
    auto item = [](quint32 id, ItemStatus status, ItemCategory category = ItemCategory::ApplicationStatus) {
        ItemData data;
        data.id = id;
        data.status = status;
        data.category = category;
        return data;
    };
    const QList<ItemData> items{
        item(1, ItemStatus::Active, ItemCategory::Hardware),
        item(2, ItemStatus::Active),
        item(3, ItemStatus::Passive),
        item(4, ItemStatus::Active, ItemCategory::Communications),
        item(5, ItemStatus::NeedsAttention, ItemCategory::Hardware),
        item(6, ItemStatus::Active),
    };
    auto ids = [](const QList<ItemData> &rows) {
        QList<quint32> list;
        for (const auto &row : rows)
            list.append(row.id);
        return list;
    };
    // Applications, communications, …, hardware; by age within a category
    QCOMPARE(ids(TrayItemsModel::select(items, TrayItemsModel::All, -1)), (QList<quint32>{2, 3, 6, 4, 1, 5}));
    QCOMPARE(ids(TrayItemsModel::select(items, TrayItemsModel::Shown, -1)), (QList<quint32>{2, 6, 4, 1, 5}));
    QCOMPARE(ids(TrayItemsModel::select(items, TrayItemsModel::Passive, -1)), (QList<quint32>{3}));
    // Two places: the one that needs attention takes one, still in order
    int hidden = 0;
    QCOMPARE(ids(TrayItemsModel::select(items, TrayItemsModel::Shown, 2, &hidden)), (QList<quint32>{2, 5}));
    QCOMPARE(hidden, 3);
    QCOMPARE(ids(TrayItemsModel::select(items, TrayItemsModel::Shown, 0, &hidden)), QList<quint32>{});
    QCOMPARE(hidden, 5);
}

void TestTray::itemsAppearWithTheirData()
{
    TrayItemsModel model;
    Tray tray;
    QCOMPARE(model.rowCount(), 0);
    FakeApp app(m_environment, {QStringLiteral("--title"), QStringLiteral("Fake chat"), QStringLiteral("--tooltip"), QStringLiteral("2 <b>new</b> messages")});
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 5000);
    QCOMPARE(tray.count(), 1);
    const QModelIndex at = model.index(0);
    QCOMPARE(at.data(TrayItemsModel::TitleRole).toString(), QStringLiteral("Fake chat"));
    QCOMPARE(at.data(TrayItemsModel::IconNameRole).toString(), QStringLiteral("internet-chat"));
    QCOMPARE(at.data(TrayItemsModel::IconSourceRole).toString(), QStringLiteral("internet-chat"));
    QCOMPARE(at.data(TrayItemsModel::StatusRole).toInt(), int(Tray::Active));
    QCOMPARE(at.data(TrayItemsModel::CategoryRole).toInt(), int(Tray::Communications));
    QCOMPARE(at.data(TrayItemsModel::ToolTipTextRole).toString(), QStringLiteral("2 new messages"));
    QCOMPARE(at.data(TrayItemsModel::KeyRole).toString(), QStringLiteral("fake-tray-item"));
    QVERIFY(at.data(TrayItemsModel::HasMenuRole).toBool());
    QVERIFY(!at.data(TrayItemsModel::ItemIsMenuRole).toBool());
    QCOMPARE(model.get(0).value(QStringLiteral("title")).toString(), QStringLiteral("Fake chat"));

    // A change of the title is one row's role, not a reset
    QSignalSpy resets(&model, &QAbstractItemModel::modelReset);
    QSignalSpy changes(&model, &QAbstractItemModel::dataChanged);
    app.send(QStringLiteral("title Renamed"));
    QTRY_COMPARE_WITH_TIMEOUT(model.index(0).data(TrayItemsModel::TitleRole).toString(), QStringLiteral("Renamed"), 5000);
    QCOMPARE(resets.count(), 0);
    QVERIFY(changes.last().at(2).value<QList<int>>().contains(TrayItemsModel::TitleRole));
    QVERIFY(!changes.last().at(2).value<QList<int>>().contains(TrayItemsModel::IconSourceRole));
}

void TestTray::statusMovesItemsBetweenFilters()
{
    TrayItemsModel shown;
    shown.setFilter(TrayItemsModel::Shown);
    TrayItemsModel passive;
    passive.setFilter(TrayItemsModel::Passive);
    Tray tray;
    FakeApp app(m_environment, {});
    QTRY_COMPARE_WITH_TIMEOUT(shown.rowCount(), 1, 5000);
    QCOMPARE(passive.rowCount(), 0);

    app.send(QStringLiteral("status Passive"));
    QTRY_COMPARE_WITH_TIMEOUT(passive.rowCount(), 1, 5000);
    QCOMPARE(shown.rowCount(), 0);

    app.send(QStringLiteral("status NeedsAttention"));
    QTRY_COMPARE_WITH_TIMEOUT(shown.rowCount(), 1, 5000);
    QCOMPARE(shown.attentionCount(), 1);
    QCOMPARE(tray.attentionCount(), 1);
    const QModelIndex at = shown.index(0);
    QVERIFY(at.data(TrayItemsModel::NeedsAttentionRole).toBool());
    // The attention icon now, the usual one as before
    QCOMPARE(at.data(TrayItemsModel::CurrentIconSourceRole).toString(), QStringLiteral("mail-unread-new"));
    QCOMPARE(at.data(TrayItemsModel::IconSourceRole).toString(), QStringLiteral("internet-chat"));

    // No place left: hidden, counted
    shown.setMaximumCount(0);
    QCOMPARE(shown.rowCount(), 0);
    QCOMPARE(shown.hiddenCount(), 1);
}

void TestTray::clicksReachTheApplication()
{
    TrayItemsModel model;
    Tray tray;
    FakeApp app(m_environment, {});
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 5000);
    const uint id = model.index(0).data(TrayItemsModel::ItemIdRole).toUInt();

    tray.activate(id, 10, 20);
    QVERIFY(app.waitFor(QStringLiteral("Activate 10 20")));
    tray.secondaryActivate(id);
    QVERIFY(app.waitFor(QStringLiteral("SecondaryActivate 0 0")));
    tray.scroll(id, 120);
    QVERIFY(app.waitFor(QStringLiteral("Scroll 120 vertical")));
    tray.scroll(id, -120, true);
    QVERIFY(app.waitFor(QStringLiteral("Scroll -120 horizontal")));
    tray.contextMenu(id, 5, 6);
    QVERIFY(app.waitFor(QStringLiteral("ContextMenu 5 6")));
}

void TestTray::menusFollowTheApplication()
{
    TrayItemsModel model;
    FakeApp app(m_environment, {QStringLiteral("--menu"), QStringLiteral("Show,-,Quit")});
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 5000);

    TrayMenu menu;
    menu.setItemId(model.index(0).data(TrayItemsModel::ItemIdRole).toUInt());
    menu.setActive(true);
    QTRY_VERIFY_WITH_TIMEOUT(menu.ready(), 5000);
    TrayMenuEntriesModel *entries = menu.entries();
    QCOMPARE(entries->rowCount(), 3);
    QCOMPARE(entries->index(0).data(TrayMenuEntriesModel::LabelRole).toString(), QStringLiteral("Show"));
    QVERIFY(entries->index(1).data(TrayMenuEntriesModel::SeparatorRole).toBool());
    QCOMPARE(entries->index(2).data(TrayMenuEntriesModel::EntryIdRole).toInt(), 3);
    QVERIFY(app.waitFor(QStringLiteral("AboutToShow 0")));
    QVERIFY(app.waitFor(QStringLiteral("Event 0 opened")));

    // The application changes a label: that row changes, by its id
    QSignalSpy resets(entries, &QAbstractItemModel::modelReset);
    QSignalSpy removed(entries, &QAbstractItemModel::rowsRemoved);
    app.send(QStringLiteral("menu Hide,-,Quit"));
    QTRY_COMPARE_WITH_TIMEOUT(entries->index(0).data(TrayMenuEntriesModel::LabelRole).toString(), QStringLiteral("Hide"), 5000);
    QCOMPARE(resets.count(), 0);
    QCOMPARE(removed.count(), 0);

    // An empty submenu model for an entry without children, the same object every time
    QCOMPARE(menu.submenu(1), menu.submenu(1));
    QCOMPARE(menu.submenu(1)->rowCount(), 0);

    QSignalSpy closed(&menu, &TrayMenu::closed);
    QSignalSpy triggered(&menu, &TrayMenu::triggered);
    menu.trigger(3);
    QCOMPARE(triggered.count(), 1);
    QCOMPARE(closed.count(), 1);
    QVERIFY(app.waitFor(QStringLiteral("Event 3 clicked")));
    QVERIFY(app.waitFor(QStringLiteral("Event 0 closed")));
    QVERIFY(app.lines().indexOf(QStringLiteral("Event 3 clicked")) < app.lines().indexOf(QStringLiteral("Event 0 closed")));

    // Opened again, closed by the shell
    menu.setActive(false);
    menu.setActive(true);
    QTRY_VERIFY_WITH_TIMEOUT(menu.ready(), 5000);
    menu.setActive(false);
    QVERIFY(!menu.ready());
}

void TestTray::pixelsBecomeFiles()
{
    TrayItemsModel model;
    FakeApp app(m_environment, {QStringLiteral("--pixmap"), QStringLiteral("ff8800")});
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 5000);
    const QString url = model.index(0).data(TrayItemsModel::IconSourceRole).toString();
    QVERIFY2(url.startsWith(QLatin1String("file://")), qPrintable(url));
    QVERIFY(QFileInfo::exists(QUrl(url).toLocalFile()));
    QVERIFY(QUrl(url).toLocalFile().startsWith(m_dir.path() + QStringLiteral("/maia/tray-tst-tray/")));

    // A new colour is a new file; a picture in colour is drawn as it is
    app.send(QStringLiteral("pixmap 0088ff"));
    QTRY_VERIFY_WITH_TIMEOUT(model.index(0).data(TrayItemsModel::IconSourceRole).toString() != url, 5000);
    QVERIFY(!model.index(0).data(TrayItemsModel::CurrentIconIsMaskRole).toBool());

    // Black on transparency (Claude, Electron): a mask, the shell's colour of text draws it
    QSignalSpy changes(&model, &QAbstractItemModel::dataChanged);
    app.send(QStringLiteral("pixmap 000000"));
    QTRY_VERIFY_WITH_TIMEOUT(model.index(0).data(TrayItemsModel::CurrentIconIsMaskRole).toBool(), 5000);
    QVERIFY(model.index(0).data(TrayItemsModel::IconIsMaskRole).toBool());
    QVERIFY(changes.last().at(2).value<QList<int>>().contains(TrayItemsModel::CurrentIconIsMaskRole));
}

void TestTray::itemsGoWithTheirApplication()
{
    TrayItemsModel model;
    auto app = std::make_unique<FakeApp>(m_environment, QStringList{});
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 1, 5000);
    TrayMenu menu;
    menu.setItemId(model.index(0).data(TrayItemsModel::ItemIdRole).toUInt());
    menu.setActive(true);
    QTRY_VERIFY_WITH_TIMEOUT(menu.ready(), 5000);
    QSignalSpy closed(&menu, &TrayMenu::closed);

    app->send(QStringLiteral("quit"));
    QTRY_COMPARE_WITH_TIMEOUT(model.rowCount(), 0, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(closed.count(), 1, 5000);
}

QTEST_MAIN(TestTray)

#include "tst_tray.moc"
