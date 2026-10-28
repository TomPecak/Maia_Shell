// TasksModel on a fake window source: rows, groups, filtering, sorting and requests, with
// QAbstractItemModelTester watching every change signal for consistency.

#include "AbstractTasksModel.h"
#include "TasksModel.h"

#include <QAbstractItemModelTester>
#include <QDateTime>
#include <QSignalSpy>
#include <QTest>

using namespace MaiaWindows;
namespace Roles = MaiaWindows::AbstractTasksModel;

// A window source the test feeds by hand; commands are recorded
class FakeSource final : public WindowSource
{
public:
    FakeSource()
    {
        setConnected(true, CanActivate | CanClose | CanMinimize | CanMaximize | CanLaunch);
    }

    using WindowSource::applySnapshot;
    using WindowSource::remove;
    using WindowSource::upsert;

    QStringList commands;

    void activate(const QString &id) override { commands << QStringLiteral("activate ") + id; }
    void close(const QString &id) override { commands << QStringLiteral("close ") + id; }
    void setState(const QString &id, State flag, bool on) override
    {
        commands << QStringLiteral("state %1 %2 %3").arg(id).arg(quint32(flag)).arg(on);
    }
    void requestMove(const QString &id) override { commands << QStringLiteral("move ") + id; }
    void requestResize(const QString &id) override { commands << QStringLiteral("resize ") + id; }
    void launchNewInstance(const QString &id) override { commands << QStringLiteral("new ") + id; }
    void launch(const QString &url) override { commands << QStringLiteral("launch ") + url; }

protected:
    void fetchIcon(const QString &, quint32) override { }
};

namespace {

WindowInfo window(const QString &id, const QString &title, const QString &app = QString(), quint32 states = 0)
{
    WindowInfo w;
    w.id = id;
    w.title = title;
    w.states = states | Closeable | Minimizable;
    if (!app.isEmpty()) {
        w.appId = app + QStringLiteral(".desktop");
        w.rawAppId = app;
        w.appName = app.section(QLatin1Char('.'), -1);
        w.launcherUrl = QStringLiteral("applications:") + w.appId;
    }
    return w;
}

QStringList displays(const TasksModel &model, const QModelIndex &parent = QModelIndex())
{
    QStringList list;
    for (int i = 0; i < model.rowCount(parent); ++i)
        list << model.index(i, 0, parent).data(Qt::DisplayRole).toString();
    return list;
}

} // namespace

class TasksModelTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init()
    {
        source = std::make_unique<FakeSource>();
        model = std::make_unique<TasksModel>(source.get(), nullptr);
        tester = std::make_unique<QAbstractItemModelTester>(model.get(), QAbstractItemModelTester::FailureReportingMode::QtTest);
    }

    void cleanup()
    {
        tester.reset();
        model.reset();
        source.reset();
    }

    void oneRowPerWindowInOrderOfAppearance()
    {
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Terminal"), QStringLiteral("org.kde.konsole")));
        source->upsert(window(QStringLiteral("b"), QStringLiteral("Mozilla"), QStringLiteral("firefox")));
        source->upsert(window(QStringLiteral("c"), QStringLiteral("Second terminal"), QStringLiteral("org.kde.konsole")));
        QCOMPARE(model->count(), 3);
        QCOMPARE(displays(*model), (QStringList{QStringLiteral("Terminal"), QStringLiteral("Mozilla"), QStringLiteral("Second terminal")}));

        const QModelIndex first = model->makeModelIndex(0);
        QCOMPARE(first.data(Roles::AppId).toString(), QStringLiteral("org.kde.konsole")); // like Plasma: no ".desktop"
        QCOMPARE(first.data(Roles::LauncherUrl).toUrl(), QUrl(QStringLiteral("applications:org.kde.konsole.desktop")));
        QCOMPARE(first.data(Roles::IsWindow).toBool(), true);
        QCOMPARE(first.data(Roles::IsGroupParent).toBool(), false);
        QCOMPARE(first.data(Roles::WinIdList).toList(), QVariantList{QStringLiteral("a")});

        source->remove(QStringLiteral("b"));
        QCOMPARE(displays(*model), (QStringList{QStringLiteral("Terminal"), QStringLiteral("Second terminal")}));
    }

    void roleNamesAreThoseOfPlasma()
    {
        const auto names = model->roleNames();
        QCOMPARE(names.value(Qt::DisplayRole), QByteArray("display"));
        QCOMPARE(names.value(Qt::DecorationRole), QByteArray("decoration"));
        QCOMPARE(names.value(Roles::IsActive), QByteArray("IsActive"));
        QCOMPARE(names.value(Roles::AppName), QByteArray("AppName"));
        QCOMPARE(names.value(Roles::LastActivated), QByteArray("LastActivated"));
        // The values of Plasma 6.6
        QCOMPARE(int(Roles::AppId), Qt::UserRole + 1);
        QCOMPARE(int(Roles::IsActive), Qt::UserRole + 16);
    }

    void windowsSkippingTheTaskbarAreLeftOut()
    {
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Popup"), QString(), SkipTaskbar));
        QCOMPARE(model->count(), 0);
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Popup")));
        QCOMPARE(model->count(), 1);
        model->setFilterSkipTaskbar(false);
        source->upsert(window(QStringLiteral("b"), QStringLiteral("Hidden"), QString(), SkipTaskbar));
        QCOMPARE(model->count(), 2);
    }

    void applicationsAreGroupedWithChildren()
    {
        model->setGroupMode(TasksModel::GroupApplications);
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Terminal"), QStringLiteral("org.kde.konsole")));
        source->upsert(window(QStringLiteral("b"), QStringLiteral("Mozilla"), QStringLiteral("firefox")));
        QCOMPARE(model->count(), 2);
        QCOMPARE(model->rowCount(model->makeModelIndex(0)), 0); // one window: a plain row

        source->upsert(window(QStringLiteral("c"), QStringLiteral("Second terminal"), QStringLiteral("org.kde.konsole")));
        QCOMPARE(model->count(), 2);
        const QModelIndex group = model->makeModelIndex(0);
        QCOMPARE(group.data(Roles::IsGroupParent).toBool(), true);
        QCOMPARE(group.data(Roles::ChildCount).toInt(), 2);
        QCOMPARE(group.data(Qt::DisplayRole).toString(), QStringLiteral("konsole")); // the application name
        QCOMPARE(displays(*model, group), (QStringList{QStringLiteral("Terminal"), QStringLiteral("Second terminal")}));
        QCOMPARE(model->makeModelIndex(0, 1).data(Qt::DisplayRole).toString(), QStringLiteral("Second terminal"));
        QCOMPARE(model->makeModelIndex(0, 1).parent(), group);

        source->remove(QStringLiteral("a"));
        QCOMPARE(model->rowCount(model->makeModelIndex(0)), 0); // back to a plain row
        QCOMPARE(model->makeModelIndex(0).data(Qt::DisplayRole).toString(), QStringLiteral("Second terminal"));
    }

    void identifiedLaterMovesToItsApplication()
    {
        model->setGroupMode(TasksModel::GroupApplications);
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Terminal"), QStringLiteral("org.kde.konsole")));
        WindowInfo late = window(QStringLiteral("b"), QStringLiteral("Starting..."));
        source->upsert(late);
        QCOMPARE(model->count(), 2);

        source->upsert(window(QStringLiteral("b"), QStringLiteral("Terminal 2"), QStringLiteral("org.kde.konsole")));
        QCOMPARE(model->count(), 1);
        QCOMPARE(model->rowCount(model->makeModelIndex(0)), 2);
    }

    void groupStateIsAnyActiveAndLatestActivation()
    {
        model->setGroupMode(TasksModel::GroupApplications);
        WindowInfo a = window(QStringLiteral("a"), QStringLiteral("One"), QStringLiteral("org.kde.konsole"));
        WindowInfo b = window(QStringLiteral("b"), QStringLiteral("Two"), QStringLiteral("org.kde.konsole"), Active);
        a.lastActivated = 1000;
        b.lastActivated = 5000;
        source->upsert(a);
        source->upsert(b);
        const QModelIndex group = model->makeModelIndex(0);
        QCOMPARE(group.data(Roles::IsActive).toBool(), true);
        QCOMPARE(group.data(Roles::LastActivated).toDateTime().toMSecsSinceEpoch(), 5000);
        QCOMPARE(model->makeModelIndex(0, 0).data(Roles::IsActive).toBool(), false);
        QCOMPARE(model->activeTask(), model->makeModelIndex(0, 1));
        QVERIFY(!model->makeModelIndex(0, 0).data(Roles::LastActivated).toDateTime().isNull());
    }

    void requestsBecomeCommands()
    {
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Terminal"), QStringLiteral("org.kde.konsole"), Active));
        model->requestActivate(model->makeModelIndex(0));
        model->requestToggleMinimized(model->makeModelIndex(0));
        model->requestClose(model->makeModelIndex(0));
        model->requestNewInstance(model->makeModelIndex(0));
        model->launch(QStringLiteral("applications:org.kde.dolphin.desktop"));
        QCOMPARE(source->commands,
                 (QStringList{QStringLiteral("activate a"), QStringLiteral("state a 2 1"), QStringLiteral("close a"),
                              QStringLiteral("new a"), QStringLiteral("launch applications:org.kde.dolphin.desktop")}));
    }

    void groupRequestsActOnAllWindows()
    {
        model->setGroupMode(TasksModel::GroupApplications);
        source->upsert(window(QStringLiteral("a"), QStringLiteral("One"), QStringLiteral("org.kde.konsole"), Minimized));
        source->upsert(window(QStringLiteral("b"), QStringLiteral("Two"), QStringLiteral("org.kde.konsole")));
        const QModelIndex group = model->makeModelIndex(0);

        model->requestActivate(group); // a group is not activated as a whole (Plasma)
        QVERIFY(source->commands.isEmpty());

        model->requestToggleMinimized(group); // not all minimized: minimize the rest
        QCOMPARE(source->commands, QStringList{QStringLiteral("state b 2 1")});

        source->commands.clear();
        source->upsert(window(QStringLiteral("b"), QStringLiteral("Two"), QStringLiteral("org.kde.konsole"), Minimized));
        model->requestToggleMinimized(model->makeModelIndex(0)); // all minimized: restore all
        QCOMPARE(source->commands, (QStringList{QStringLiteral("state a 2 0"), QStringLiteral("state b 2 0")}));

        source->commands.clear();
        model->requestClose(model->makeModelIndex(0));
        QCOMPARE(source->commands, (QStringList{QStringLiteral("close a"), QStringLiteral("close b")}));
    }

    void alphabeticalSortFollowsChanges()
    {
        model->setSortMode(TasksModel::SortAlphabetical);
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Zeta")));
        source->upsert(window(QStringLiteral("b"), QStringLiteral("Alpha")));
        source->upsert(window(QStringLiteral("c"), QStringLiteral("Mid")));
        QCOMPARE(displays(*model), (QStringList{QStringLiteral("Alpha"), QStringLiteral("Mid"), QStringLiteral("Zeta")}));

        source->upsert(window(QStringLiteral("b"), QStringLiteral("Omega")));
        QCOMPARE(displays(*model), (QStringList{QStringLiteral("Mid"), QStringLiteral("Omega"), QStringLiteral("Zeta")}));
    }

    void manualMove()
    {
        for (const char *id : {"a", "b", "c"})
            source->upsert(window(QString::fromLatin1(id), QString::fromLatin1(id)));
        QVERIFY(model->move(0, 2));
        QCOMPARE(displays(*model), (QStringList{QStringLiteral("b"), QStringLiteral("c"), QStringLiteral("a")}));
        QVERIFY(model->move(2, 0));
        QCOMPARE(displays(*model), (QStringList{QStringLiteral("a"), QStringLiteral("b"), QStringLiteral("c")}));
        QVERIFY(!model->move(0, 3));
    }

    void snapshotAfterReconnectionChangesOnlyWhatDiffers()
    {
        source->upsert(window(QStringLiteral("a"), QStringLiteral("Kept")));
        source->upsert(window(QStringLiteral("b"), QStringLiteral("Closed meanwhile")));
        QSignalSpy resets(model.get(), &QAbstractItemModel::modelReset);
        QSignalSpy removals(model.get(), &QAbstractItemModel::rowsRemoved);
        QSignalSpy inserts(model.get(), &QAbstractItemModel::rowsInserted);

        source->applySnapshot({window(QStringLiteral("a"), QStringLiteral("Kept")), window(QStringLiteral("c"), QStringLiteral("New"))});
        QCOMPARE(resets.count(), 0);
        QCOMPARE(removals.count(), 1);
        QCOMPARE(inserts.count(), 1);
        QCOMPARE(displays(*model), (QStringList{QStringLiteral("Kept"), QStringLiteral("New")}));
    }

    void attentionIsReported()
    {
        QSignalSpy spy(model.get(), &TasksModel::anyTaskDemandsAttentionChanged);
        source->upsert(window(QStringLiteral("a"), QStringLiteral("x"), QString(), DemandsAttention));
        QVERIFY(model->anyTaskDemandsAttention());
        source->upsert(window(QStringLiteral("a"), QStringLiteral("x")));
        QVERIFY(!model->anyTaskDemandsAttention());
        QCOMPARE(spy.count(), 2);
    }

    // A change reports only the roles that differ, so views re-evaluate only what depends on them
    // (a window being dragged changes its geometry every frame)
    void changesReportOnlyTheirRoles()
    {
        WindowInfo w = window(QStringLiteral("a"), QStringLiteral("Terminal"), QStringLiteral("org.kde.konsole"));
        source->upsert(w);
        QSignalSpy spy(model.get(), &QAbstractItemModel::dataChanged);

        w.geometry = QRect(10, 20, 300, 200);
        source->upsert(w);
        w.title = QStringLiteral("vim");
        source->upsert(w);
        w.states |= Active;
        w.lastActivated = 1000;
        source->upsert(w);

        QCOMPARE(changes(spy),
                 (QList<Change>{{model->makeModelIndex(0), {Roles::Geometry, Roles::ScreenGeometry}},
                                {model->makeModelIndex(0), {Qt::DisplayRole}},
                                {model->makeModelIndex(0), {Roles::IsActive, Roles::LastActivated}}}));
    }

    void groupRowGetsOnlyTheRolesThatDependOnTheChange()
    {
        model->setGroupMode(TasksModel::GroupApplications);
        WindowInfo first = window(QStringLiteral("a"), QStringLiteral("One"), QStringLiteral("org.kde.konsole"));
        WindowInfo second = window(QStringLiteral("b"), QStringLiteral("Two"), QStringLiteral("org.kde.konsole"));
        source->upsert(first);
        source->upsert(second);
        const QModelIndex group = model->makeModelIndex(0);
        QSignalSpy spy(model.get(), &QAbstractItemModel::dataChanged);

        // Geometry and title of a window are not shown by its group
        second.geometry = QRect(0, 0, 100, 100);
        source->upsert(second);
        first.title = QStringLiteral("One, renamed");
        source->upsert(first);
        // Activation is: the group is active when any of its windows is
        second.states |= Active;
        source->upsert(second);

        QCOMPARE(changes(spy),
                 (QList<Change>{{model->makeModelIndex(0, 1), {Roles::Geometry, Roles::ScreenGeometry}},
                                {model->makeModelIndex(0, 0), {Qt::DisplayRole}},
                                {model->makeModelIndex(0, 1), {Roles::IsActive}},
                                {group, {Roles::IsActive}}}));
    }

private:
    using Change = std::pair<QModelIndex, QList<int>>;

    // The (index, roles) of each dataChanged signal; every signal here covers one row
    static QList<Change> changes(const QSignalSpy &spy)
    {
        QList<Change> list;
        for (const QList<QVariant> &arguments : spy) {
            const auto first = arguments.at(0).value<QModelIndex>();
            const auto last = arguments.at(1).value<QModelIndex>();
            if (first != last)
                qWarning() << "dataChanged over several rows";
            list.append({first, arguments.at(2).value<QList<int>>()});
        }
        return list;
    }

    std::unique_ptr<FakeSource> source;
    std::unique_ptr<TasksModel> model;
    std::unique_ptr<QAbstractItemModelTester> tester;
};

QTEST_MAIN(TasksModelTest)
#include "tst_tasksmodel.moc"
