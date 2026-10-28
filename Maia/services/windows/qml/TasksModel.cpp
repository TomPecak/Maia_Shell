#include "TasksModel.h"

#include "AbstractTasksModel.h"
#include "ServiceConnection.h"

#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QMetaEnum>
#include <QUrl>

#include <algorithm>

namespace MaiaWindows {

using namespace AbstractTasksModel;

namespace {

// Each state bit and the roles that show it (windowData)
struct StateRole {
    State state;
    int role;
};
constexpr StateRole stateRoles[] = {
    {Active, IsActive},
    {Minimized, IsMinimized},
    {Minimized, IsHidden},
    {Maximized, IsMaximized},
    {Fullscreen, IsFullScreen},
    {KeepAbove, IsKeepAbove},
    {KeepBelow, IsKeepBelow},
    {OnAllDesktops, IsOnAllVirtualDesktops},
    {DemandsAttention, IsDemandingAttention},
    {Closeable, IsClosable},
    {Minimizable, IsMinimizable},
    {Maximizable, IsMaximizable},
    {Fullscreenable, IsFullScreenable},
    {State::SkipTaskbar, AbstractTasksModel::SkipTaskbar},
    {Shaded, IsShaded},
    {Movable, IsMovable},
    {Resizable, IsResizable},
    {VirtualDesktopChangeable, IsVirtualDesktopsChangeable},
};

// The roles of a window row whose value differs between the two states of the window. Views
// re-evaluate only bindings on these roles: a window being dragged changes only Geometry, and a
// task bar button that does not show it does no work.
QList<int> changedRoles(const WindowInfo &a, const WindowInfo &b)
{
    QList<int> roles;
    if (a.title != b.title)
        roles << Qt::DisplayRole;
    if (a.iconName != b.iconName || a.iconSerial != b.iconSerial)
        roles << Qt::DecorationRole;
    if (a.appId != b.appId)
        roles << AppId;
    if (a.appName != b.appName)
        roles << AppName;
    if (a.genericName != b.genericName)
        roles << GenericName;
    if (a.launcherUrl != b.launcherUrl)
        roles << LauncherUrl << LauncherUrlWithoutIcon;
    if (a.canLaunchNewInstance != b.canLaunchNewInstance)
        roles << CanLaunchNewInstance;
    if (a.pid != b.pid)
        roles << AppPid;
    const quint32 states = a.states ^ b.states;
    for (const StateRole &entry : stateRoles) {
        if (states & entry.state)
            roles << entry.role;
    }
    if (a.geometry != b.geometry)
        roles << Geometry << ScreenGeometry;
    if (a.virtualDesktops != b.virtualDesktops)
        roles << VirtualDesktops;
    if (a.lastActivated != b.lastActivated)
        roles << LastActivated;
    return roles;
}

// Roles of a group row computed from all its windows (groupData); the others are those of its
// first window, or constant (Geometry, AppPid, IsMovable, IsResizable)
bool isAggregatedGroupRole(int role)
{
    switch (role) {
    case IsActive:
    case IsDemandingAttention:
    case IsClosable:
    case IsMaximizable:
    case IsMaximized:
    case IsMinimizable:
    case IsMinimized:
    case IsHidden:
    case IsKeepAbove:
    case IsKeepBelow:
    case IsFullScreenable:
    case IsFullScreen:
    case IsShaded:
    case AbstractTasksModel::SkipTaskbar:
    case VirtualDesktops:
    case LastActivated:
        return true;
    default:
        return false;
    }
}

// The roles of a group row that change with these roles of one of its windows
QList<int> groupRoles(const QList<int> &windowRoles, bool firstWindow)
{
    static const QList<int> constant{Geometry, ScreenGeometry, AppPid, IsMovable, IsResizable};
    QList<int> roles;
    for (int role : windowRoles) {
        if (isAggregatedGroupRole(role)) {
            roles << role;
        } else if (firstWindow && !constant.contains(role) && role != Qt::DisplayRole) {
            roles << role;
        }
    }
    // The name of a group is that of its application, not the title of its first window
    if (firstWindow && (windowRoles.contains(AppName) || windowRoles.contains(AppId)))
        roles << Qt::DisplayRole;
    return roles;
}

} // namespace

TasksModel::TasksModel(QObject *parent)
    : TasksModel(nullptr, parent)
{
}

TasksModel::TasksModel(WindowSource *source, QObject *parent)
    : QAbstractItemModel(parent)
{
    setSource(source ? source : ServiceConnection::instance());
}

void TasksModel::setSource(WindowSource *source)
{
    m_source = source;
    connect(source, &WindowSource::windowAdded, this, [this](const WindowInfo &window) {
        if (accepts(window))
            insertWindow(window);
    });
    connect(source, &WindowSource::windowRemoved, this, [this](const WindowInfo &window) { removeWindow(window.id); });
    connect(source, &WindowSource::windowChanged, this, &TasksModel::onWindowChanged);
    connect(source, &WindowSource::iconChanged, this, &TasksModel::onIconChanged);
    connect(source, &WindowSource::connectedChanged, this, &TasksModel::connectedChanged);
    rebuild();
}

// --- Rows ---

bool TasksModel::accepts(const WindowInfo &window) const
{
    return !(m_filterSkipTaskbar && window.has(State::SkipTaskbar));
}

QString TasksModel::groupKey(const WindowInfo &window) const
{
    if (m_groupMode == GroupApplications) {
        if (!window.appId.isEmpty())
            return QStringLiteral("app:") + window.appId;
        if (!window.rawAppId.isEmpty())
            return QStringLiteral("raw:") + window.rawAppId;
    }
    return QStringLiteral("window:") + window.id;
}

int TasksModel::rowOfKey(const QString &key) const
{
    for (int i = 0; i < m_rows.size(); ++i) {
        if (m_rows.at(i).key == key)
            return i;
    }
    return -1;
}

bool TasksModel::locate(const QString &id, int &row, int &child) const
{
    for (int r = 0; r < m_rows.size(); ++r) {
        const int c = int(m_rows.at(r).windows.indexOf(id));
        if (c >= 0) {
            row = r;
            child = m_rows.at(r).windows.size() > 1 ? c : -1;
            return true;
        }
    }
    return false;
}

QModelIndex TasksModel::indexOfWindow(const QString &id) const
{
    int row, child;
    if (!locate(id, row, child))
        return {};
    return makeModelIndex(row, child);
}

void TasksModel::rebuild()
{
    beginResetModel();
    m_rows.clear();
    if (m_source) {
        for (const WindowInfo &window : m_source->windows()) {
            if (!accepts(window))
                continue;
            const QString key = groupKey(window);
            const int row = rowOfKey(key);
            if (row >= 0)
                m_rows[row].windows.append(window.id);
            else
                m_rows.append(Row{m_nextUid++, key, {window.id}});
        }
        if (m_sortMode == SortAlphabetical || m_sortMode == SortLastActivated)
            std::stable_sort(m_rows.begin(), m_rows.end(), [this](const Row &a, const Row &b) { return lessThan(a, b); });
    }
    endResetModel();
    Q_EMIT countChanged();
    updateSummary();
}

void TasksModel::insertWindow(const WindowInfo &window)
{
    const QString key = groupKey(window);
    const int row = rowOfKey(key);
    if (row < 0) {
        Row newRow{m_nextUid++, key, {window.id}};
        int position = int(m_rows.size());
        if (m_sortMode == SortAlphabetical || m_sortMode == SortLastActivated) {
            position = int(std::upper_bound(m_rows.cbegin(), m_rows.cend(), newRow,
                                            [this](const Row &a, const Row &b) { return lessThan(a, b); })
                           - m_rows.cbegin());
        }
        beginInsertRows(QModelIndex(), position, position);
        m_rows.insert(position, newRow);
        endInsertRows();
        Q_EMIT countChanged();
    } else {
        // A row of one window becomes a group with both windows as children (it had no children)
        Row &target = m_rows[row];
        const int count = int(target.windows.size());
        const int first = count == 1 ? 0 : count;
        beginInsertRows(index(row, 0), first, count);
        target.windows.append(window.id);
        endInsertRows();
        notifyRowChanged(row);
        sortRows();
    }
    updateSummary();
}

void TasksModel::removeWindow(const QString &id)
{
    int row, child;
    if (!locate(id, row, child))
        return;
    Row &target = m_rows[row];
    const int count = int(target.windows.size());
    if (count == 1) {
        beginRemoveRows(QModelIndex(), row, row);
        m_rows.removeAt(row);
        endRemoveRows();
        Q_EMIT countChanged();
    } else {
        // A group of two becomes a row of one window: both children go
        const int first = count == 2 ? 0 : child;
        const int last = count == 2 ? 1 : child;
        beginRemoveRows(index(row, 0), first, last);
        target.windows.removeOne(id);
        endRemoveRows();
        notifyRowChanged(row);
        sortRows();
    }
    updateSummary();
}

void TasksModel::onWindowChanged(const WindowInfo &before, const WindowInfo &after)
{
    int row, child;
    const bool shown = locate(after.id, row, child);
    if (!shown || !accepts(after) || groupKey(before) != groupKey(after)) {
        // Moves between groups, or in or out of the model
        removeWindow(after.id);
        if (accepts(after))
            insertWindow(after);
        return;
    }
    const QList<int> roles = changedRoles(before, after);
    if (roles.isEmpty())
        return;
    const QModelIndex rowIndex = index(row, 0);
    if (child < 0) {
        Q_EMIT dataChanged(rowIndex, rowIndex, roles);
    } else {
        const QModelIndex childIndex = makeModelIndex(row, child);
        Q_EMIT dataChanged(childIndex, childIndex, roles);
        const QList<int> rowRoles = groupRoles(roles, child == 0);
        if (!rowRoles.isEmpty())
            Q_EMIT dataChanged(rowIndex, rowIndex, rowRoles);
    }

    const bool sortChanged = (m_sortMode == SortAlphabetical && (before.title != after.title || before.appName != after.appName))
        || (m_sortMode == SortLastActivated && before.lastActivated != after.lastActivated);
    if (sortChanged)
        sortRows();
    if ((before.states ^ after.states) & (Active | DemandsAttention))
        updateSummary();
}

void TasksModel::onIconChanged(const QString &id)
{
    int row, child;
    if (!locate(id, row, child))
        return;
    const QList<int> roles{Qt::DecorationRole};
    if (child >= 0) {
        const QModelIndex changed = makeModelIndex(row, child);
        Q_EMIT dataChanged(changed, changed, roles);
    }
    // A group shows the icon of its first window
    if (child <= 0) {
        const QModelIndex changed = index(row, 0);
        Q_EMIT dataChanged(changed, changed, roles);
    }
}

void TasksModel::notifyRowChanged(int row)
{
    const QModelIndex changed = index(row, 0);
    Q_EMIT dataChanged(changed, changed);
}

bool TasksModel::lessThan(const Row &a, const Row &b) const
{
    const auto windows = [this](const Row &row) {
        QList<const WindowInfo *> list;
        for (const QString &id : row.windows) {
            if (const WindowInfo *window = m_source ? m_source->window(id) : nullptr)
                list.append(window);
        }
        return list;
    };
    const auto wa = windows(a);
    const auto wb = windows(b);
    if (wa.isEmpty() || wb.isEmpty())
        return false;
    if (m_sortMode == SortLastActivated) {
        const auto last = [](const QList<const WindowInfo *> &list) {
            qint64 time = 0;
            for (const WindowInfo *window : list)
                time = std::max(time, window->lastActivated);
            return time;
        };
        return last(wa) > last(wb); // the most recent first
    }
    // SortAlphabetical: by application name, windows without one by title
    const auto name = [](const WindowInfo *window) { return window->appName.isEmpty() ? window->title : window->appName; };
    return QString::localeAwareCompare(name(wa.first()), name(wb.first())) < 0;
}

void TasksModel::sortRows()
{
    if (m_sortMode != SortAlphabetical && m_sortMode != SortLastActivated)
        return;
    QList<Row> sorted = m_rows;
    std::stable_sort(sorted.begin(), sorted.end(), [this](const Row &a, const Row &b) { return lessThan(a, b); });
    // Moves one row at a time to its place: few rows, few moves, and the views animate them
    for (int target = 0; target < sorted.size(); ++target) {
        int current = target;
        while (m_rows.at(current).uid != sorted.at(target).uid)
            ++current;
        if (current == target)
            continue;
        beginMoveRows(QModelIndex(), current, current, QModelIndex(), target);
        m_rows.move(current, target);
        endMoveRows();
    }
}

void TasksModel::updateSummary()
{
    const bool attention = anyTaskDemandsAttention();
    if (attention != m_anyDemandsAttention) {
        m_anyDemandsAttention = attention;
        Q_EMIT anyTaskDemandsAttentionChanged();
    }
    QString active;
    if (m_source) {
        for (const WindowInfo &window : m_source->windows()) {
            if (window.has(Active))
                active = window.id;
        }
    }
    if (active != m_activeWindow) {
        m_activeWindow = active;
        Q_EMIT activeTaskChanged();
    }
}

// --- QAbstractItemModel ---

QModelIndex TasksModel::index(int row, int column, const QModelIndex &parent) const
{
    if (column != 0 || row < 0)
        return {};
    if (!parent.isValid())
        return row < m_rows.size() ? createIndex(row, 0, quintptr(0)) : QModelIndex();
    if (parent.internalId() != 0 || parent.row() >= m_rows.size())
        return {};
    const Row &group = m_rows.at(parent.row());
    if (group.windows.size() < 2 || row >= group.windows.size())
        return {};
    return createIndex(row, 0, group.uid);
}

QModelIndex TasksModel::parent(const QModelIndex &child) const
{
    if (!child.isValid() || child.internalId() == 0)
        return {};
    for (int r = 0; r < m_rows.size(); ++r) {
        if (m_rows.at(r).uid == child.internalId())
            return createIndex(r, 0, quintptr(0));
    }
    return {};
}

int TasksModel::rowCount(const QModelIndex &parent) const
{
    if (!parent.isValid())
        return int(m_rows.size());
    if (parent.internalId() != 0 || parent.row() >= m_rows.size())
        return 0;
    const int windows = int(m_rows.at(parent.row()).windows.size());
    return windows > 1 ? windows : 0;
}

int TasksModel::columnCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return 1;
}

bool TasksModel::hasChildren(const QModelIndex &parent) const
{
    return rowCount(parent) > 0;
}

QModelIndex TasksModel::makeModelIndex(int row, int childRow) const
{
    const QModelIndex top = index(row, 0);
    return childRow < 0 ? top : index(childRow, 0, top);
}

QPersistentModelIndex TasksModel::makePersistentModelIndex(int row, int childRow) const
{
    return QPersistentModelIndex(makeModelIndex(row, childRow));
}

const WindowInfo *TasksModel::windowAt(const QModelIndex &index) const
{
    if (!m_source || !index.isValid() || index.model() != this)
        return nullptr;
    if (index.internalId() == 0) {
        const Row &row = m_rows.at(index.row());
        return row.windows.size() == 1 ? m_source->window(row.windows.first()) : nullptr;
    }
    const QModelIndex parentIndex = parent(index);
    if (!parentIndex.isValid())
        return nullptr;
    return m_source->window(m_rows.at(parentIndex.row()).windows.value(index.row()));
}

QList<const WindowInfo *> TasksModel::windowsOf(const QModelIndex &index) const
{
    QList<const WindowInfo *> list;
    if (!m_source || !index.isValid() || index.model() != this)
        return list;
    if (const WindowInfo *window = windowAt(index)) {
        list.append(window);
        return list;
    }
    if (index.internalId() == 0) {
        for (const QString &id : m_rows.at(index.row()).windows) {
            if (const WindowInfo *window = m_source->window(id))
                list.append(window);
        }
    }
    return list;
}

QVariant TasksModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.model() != this)
        return {};
    if (const WindowInfo *window = windowAt(index))
        return windowData(*window, role);
    if (index.internalId() == 0)
        return groupData(m_rows.at(index.row()), role);
    return {};
}

QIcon TasksModel::iconFor(const WindowInfo &window) const
{
    if (!window.iconName.isEmpty()) {
        if (QDir::isAbsolutePath(window.iconName))
            return QIcon(window.iconName);
        auto cached = m_themeIcons.constFind(window.iconName);
        if (cached == m_themeIcons.cend()) {
            const QIcon icon = QIcon::hasThemeIcon(window.iconName) ? QIcon::fromTheme(window.iconName) : QIcon();
            cached = m_themeIcons.insert(window.iconName, icon);
        }
        if (!cached->isNull())
            return *cached;
    }
    // No icon by name: the bitmap the window gave the compositor (fetched once, then cached)
    const QIcon bitmap = m_source ? m_source->bitmapIcon(window) : QIcon();
    if (!bitmap.isNull())
        return bitmap;
    return QIcon::fromTheme(QStringLiteral("application-x-executable"));
}

QVariant TasksModel::windowData(const WindowInfo &w, int role) const
{
    const quint32 caps = m_source ? m_source->capabilities() : 0;
    switch (role) {
    case Qt::DisplayRole:
        return w.title;
    case Qt::DecorationRole:
        return iconFor(w);
    case AppId: {
        // Plasma: the desktop entry id without ".desktop"
        QString id = w.appId;
        if (id.endsWith(QLatin1String(".desktop")))
            id.chop(8);
        return id;
    }
    case AppName:
        return w.appName;
    case GenericName:
        return w.genericName;
    case LauncherUrl:
    case LauncherUrlWithoutIcon:
        return w.launcherUrl.isEmpty() ? QVariant() : QVariant(QUrl(w.launcherUrl));
    case WinIdList:
        return QVariantList{w.id};
    case MimeType:
        return QStringLiteral("windowsystem/winid");
    case IsWindow:
        return true;
    case IsStartup:
    case IsLauncher:
    case HasLauncher:
    case IsGroupParent:
        return false;
    case ChildCount:
        return 0;
    case IsGroupable:
        return true;
    case IsActive:
        return w.has(Active);
    case IsClosable:
        return w.has(Closeable) && (caps & CanClose);
    case IsMovable:
        return w.has(Movable) && (caps & CanMoveResize);
    case IsResizable:
        return w.has(Resizable) && (caps & CanMoveResize);
    case IsMaximizable:
        return w.has(Maximizable) && (caps & CanMaximize);
    case IsMaximized:
        return w.has(Maximized);
    case IsMinimizable:
        return w.has(Minimizable) && (caps & CanMinimize);
    case IsMinimized:
    case IsHidden:
        return w.has(Minimized);
    case IsKeepAbove:
        return w.has(KeepAbove);
    case IsKeepBelow:
        return w.has(KeepBelow);
    case IsFullScreenable:
        return w.has(Fullscreenable) && (caps & CanFullscreen);
    case IsFullScreen:
        return w.has(Fullscreen);
    case IsShadeable:
        return false; // shading is not in the contract
    case IsShaded:
        return w.has(Shaded);
    case IsVirtualDesktopsChangeable:
        return w.has(VirtualDesktopChangeable) && (caps & CanChangeVirtualDesktops);
    case VirtualDesktops:
        return w.virtualDesktops;
    case IsOnAllVirtualDesktops:
        return w.has(OnAllDesktops);
    case Geometry:
        return w.geometry;
    case IsDemandingAttention:
        return w.has(DemandsAttention);
    case AbstractTasksModel::SkipTaskbar:
        return w.has(State::SkipTaskbar);
    case SkipPager:
        return false;
    case AppPid:
        return w.pid;
    case StackingOrder:
        return -1;
    case LastActivated:
        return w.lastActivated > 0 ? QDateTime::fromMSecsSinceEpoch(w.lastActivated) : QDateTime();
    case Activities:
        return QStringList();
    case CanLaunchNewInstance:
        return w.canLaunchNewInstance && (caps & CanLaunch);
    case HasNoBorder:
    case CanSetNoBorder:
    case IsExcludedFromCapture:
        return false;
    default:
        return {};
    }
}

QVariant TasksModel::groupData(const Row &row, int role) const
{
    QList<const WindowInfo *> windows;
    for (const QString &id : row.windows) {
        if (const WindowInfo *window = m_source ? m_source->window(id) : nullptr)
            windows.append(window);
    }
    if (windows.isEmpty())
        return {};
    const auto any = [&](State state) {
        return std::any_of(windows.cbegin(), windows.cend(), [state](const WindowInfo *w) { return w->has(state); });
    };
    const auto all = [&](int role) {
        return std::all_of(windows.cbegin(), windows.cend(),
                           [&](const WindowInfo *w) { return windowData(*w, role).toBool(); });
    };
    const WindowInfo &first = *windows.first();

    switch (role) {
    case Qt::DisplayRole:
        // Plasma: the application name, or its id when the name is not known
        return first.appName.isEmpty() ? windowData(first, AppId) : QVariant(first.appName);
    case WinIdList: {
        QVariantList ids;
        for (const WindowInfo *window : windows)
            ids.append(window->id);
        return ids;
    }
    case MimeType:
        return QStringLiteral("windowsystem/multiple-winids");
    case IsGroupParent:
        return true;
    case ChildCount:
        return int(windows.size());
    case IsActive:
        return any(Active);
    case IsDemandingAttention:
        return any(DemandsAttention);
    case IsMovable:
    case IsResizable:
        return false; // moving a group makes no sense
    case IsClosable:
    case IsMaximizable:
    case IsMaximized:
    case IsMinimizable:
    case IsMinimized:
    case IsHidden:
    case IsKeepAbove:
    case IsKeepBelow:
    case IsFullScreenable:
    case IsFullScreen:
    case IsShaded:
    case AbstractTasksModel::SkipTaskbar:
        return all(role);
    case VirtualDesktops: {
        QStringList desktops;
        for (const WindowInfo *window : windows)
            desktops.append(window->virtualDesktops);
        desktops.removeDuplicates();
        return desktops;
    }
    case Geometry:
    case AppPid:
        return {};
    case LastActivated: {
        qint64 last = 0;
        for (const WindowInfo *window : windows)
            last = std::max(last, window->lastActivated);
        return last > 0 ? QDateTime::fromMSecsSinceEpoch(last) : QDateTime();
    }
    default:
        // The rest (icon, application, launcher) is that of the first window
        return windowData(first, role);
    }
}

QHash<int, QByteArray> TasksModel::roleNames() const
{
    QHash<int, QByteArray> names = QAbstractItemModel::roleNames();
    const QMetaEnum roles = QMetaEnum::fromType<AdditionalRoles>();
    for (int i = 0; i < roles.keyCount(); ++i)
        names.insert(roles.value(i), roles.key(i));
    return names;
}

// --- Properties ---

void TasksModel::setGroupMode(GroupMode mode)
{
    if (m_groupMode == mode)
        return;
    m_groupMode = mode;
    rebuild();
    Q_EMIT groupModeChanged();
}

void TasksModel::setGroupInline(bool groupInline)
{
    if (m_groupInline == groupInline)
        return;
    if (groupInline)
        qWarning() << "Maia.Windows TasksModel: groupInline is not supported, groups keep their children";
    m_groupInline = groupInline;
    Q_EMIT groupInlineChanged();
}

void TasksModel::setSortMode(SortMode mode)
{
    if (m_sortMode == mode)
        return;
    m_sortMode = mode;
    rebuild();
    Q_EMIT sortModeChanged();
}

void TasksModel::setFilterSkipTaskbar(bool filter)
{
    if (m_filterSkipTaskbar == filter)
        return;
    m_filterSkipTaskbar = filter;
    rebuild();
    Q_EMIT filterSkipTaskbarChanged();
}

bool TasksModel::anyTaskDemandsAttention() const
{
    for (const Row &row : m_rows) {
        for (const QString &id : row.windows) {
            const WindowInfo *window = m_source ? m_source->window(id) : nullptr;
            if (window && window->has(DemandsAttention))
                return true;
        }
    }
    return false;
}

QModelIndex TasksModel::activeTask() const
{
    return m_activeWindow.isEmpty() ? QModelIndex() : indexOfWindow(m_activeWindow);
}

bool TasksModel::connected() const
{
    return m_source && m_source->isConnected();
}

// --- Requests ---

void TasksModel::requestActivate(const QModelIndex &index)
{
    if (const WindowInfo *window = windowAt(index))
        m_source->activate(window->id);
}

void TasksModel::requestNewInstance(const QModelIndex &index)
{
    const auto windows = windowsOf(index);
    if (!windows.isEmpty())
        m_source->launchNewInstance(windows.first()->id);
}

void TasksModel::requestClose(const QModelIndex &index)
{
    for (const WindowInfo *window : windowsOf(index))
        m_source->close(window->id);
}

void TasksModel::requestMove(const QModelIndex &index)
{
    if (const WindowInfo *window = windowAt(index))
        m_source->requestMove(window->id);
}

void TasksModel::requestResize(const QModelIndex &index)
{
    if (const WindowInfo *window = windowAt(index))
        m_source->requestResize(window->id);
}

void TasksModel::toggleState(const QModelIndex &index, State state)
{
    const auto windows = windowsOf(index);
    if (windows.isEmpty())
        return;
    // One window: toggles. A group: all get the state, unless all have it already
    const bool goal = !std::all_of(windows.cbegin(), windows.cend(), [state](const WindowInfo *w) { return w->has(state); });
    // Copy of the ids first: the commands do not change the list now, but keep this independent of it
    QStringList ids;
    for (const WindowInfo *window : windows) {
        if (window->has(state) != goal)
            ids.append(window->id);
    }
    for (const QString &id : std::as_const(ids))
        m_source->setState(id, state, goal);
}

void TasksModel::requestToggleMinimized(const QModelIndex &index)
{
    toggleState(index, Minimized);
}

void TasksModel::requestToggleMaximized(const QModelIndex &index)
{
    toggleState(index, Maximized);
}

void TasksModel::requestToggleKeepAbove(const QModelIndex &index)
{
    toggleState(index, KeepAbove);
}

void TasksModel::requestToggleKeepBelow(const QModelIndex &index)
{
    toggleState(index, KeepBelow);
}

void TasksModel::requestToggleFullScreen(const QModelIndex &index)
{
    toggleState(index, Fullscreen);
}

void TasksModel::requestPublishDelegateGeometry(const QModelIndex &index, const QRect &geometry, QObject *delegate)
{
    // Tied to the surface of the calling client (set_minimized_geometry), so it cannot go through
    // the service; to be done in the client with the compositor directly
    Q_UNUSED(index)
    Q_UNUSED(geometry)
    Q_UNUSED(delegate)
}

bool TasksModel::move(int row, int newPos, const QModelIndex &parent)
{
    if (parent.isValid() || (m_sortMode != SortManual && m_sortMode != SortDisabled))
        return false;
    if (row < 0 || row >= m_rows.size() || newPos < 0 || newPos >= m_rows.size() || row == newPos)
        return false;
    // beginMoveRows wants the position before the move
    beginMoveRows(QModelIndex(), row, row, QModelIndex(), newPos > row ? newPos + 1 : newPos);
    m_rows.move(row, newPos);
    endMoveRows();
    return true;
}

void TasksModel::launch(const QString &launcherUrl)
{
    if (m_source)
        m_source->launch(launcherUrl);
}

} // namespace MaiaWindows
