#pragma once

// The task model for taskbars, docks and switchers: the API of TasksModel from KDE Plasma
// (org.kde.taskmanager), on top of the Maia window service.
//
//   import Maia.Windows
//
//   TasksModel {
//       id: tasksModel
//       groupMode: TasksModel.GroupApplications   // one row per application
//   }
//   Repeater {
//       model: tasksModel
//       delegate: Button {
//           icon.source: ...model.decoration, text: model.display, checked: model.IsActive
//           onClicked: tasksModel.requestActivate(tasksModel.makeModelIndex(index))
//       }
//   }
//
// Rows:
// - GroupDisabled: one row per window.
// - GroupApplications: one row per application. An application with one window is a plain row;
//   with more windows the row is a group parent (IsGroupParent) and its windows are its children
//   (rowCount(parent), index(i, 0, parent)), like Plasma with groupInline: false.
//
// Differences from Plasma: no launchers (pinned applications belong to a future service), no
// startup notifications, no activities, no filtering by screen or desktop yet;
// requestPublishDelegateGeometry does nothing (the minimize animation target is tied to the
// surface of the client, it cannot go through a service).

#include "WindowSource.h"

#include <QAbstractItemModel>
#include <QHash>
#include <QIcon>
#include <QPointer>
#include <QRect>
#include <QtQml/qqmlregistration.h>

namespace MaiaWindows {

class TasksModel : public QAbstractItemModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(GroupMode groupMode READ groupMode WRITE setGroupMode NOTIFY groupModeChanged)
    // Accepted for compatibility; only false (groups have children) is supported
    Q_PROPERTY(bool groupInline READ groupInline WRITE setGroupInline NOTIFY groupInlineChanged)
    Q_PROPERTY(SortMode sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)
    // Windows that asked not to be on a taskbar are left out (default true)
    Q_PROPERTY(bool filterSkipTaskbar READ filterSkipTaskbar WRITE setFilterSkipTaskbar NOTIFY filterSkipTaskbarChanged)
    Q_PROPERTY(bool anyTaskDemandsAttention READ anyTaskDemandsAttention NOTIFY anyTaskDemandsAttentionChanged)
    Q_PROPERTY(QModelIndex activeTask READ activeTask NOTIFY activeTaskChanged)
    // Maia: whether the window service is connected (the rows stay while it is not)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    // The values of Plasma; the modes without support here sort like SortManual
    enum SortMode {
        SortDisabled = 0,
        SortManual,
        SortAlphabetical,
        SortVirtualDesktop,
        SortActivity,
        SortLastActivated,
        SortWindowPositionHorizontal,
    };
    Q_ENUM(SortMode)

    enum GroupMode {
        GroupDisabled = 0,
        GroupApplications,
    };
    Q_ENUM(GroupMode)

    // source: where the windows come from; null = the window service of this process
    explicit TasksModel(QObject *parent = nullptr);
    TasksModel(WindowSource *source, QObject *parent);

    // --- QAbstractItemModel ---
    QModelIndex index(int row, int column, const QModelIndex &parent = QModelIndex()) const override;
    QModelIndex parent(const QModelIndex &child) const override;
    Q_INVOKABLE int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    bool hasChildren(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return int(m_rows.size()); }
    GroupMode groupMode() const { return m_groupMode; }
    void setGroupMode(GroupMode mode);
    bool groupInline() const { return m_groupInline; }
    void setGroupInline(bool groupInline);
    SortMode sortMode() const { return m_sortMode; }
    void setSortMode(SortMode mode);
    bool filterSkipTaskbar() const { return m_filterSkipTaskbar; }
    void setFilterSkipTaskbar(bool filter);
    bool anyTaskDemandsAttention() const;
    QModelIndex activeTask() const;
    bool connected() const;

    // --- Plasma API ---
    Q_INVOKABLE QModelIndex makeModelIndex(int row, int childRow = -1) const;
    Q_INVOKABLE QPersistentModelIndex makePersistentModelIndex(int row, int childRow = -1) const;

    // A window: activates it (and restores it when minimized). A group: nothing (as in Plasma; a
    // group delegate decides itself which window to activate)
    Q_INVOKABLE void requestActivate(const QModelIndex &index);
    Q_INVOKABLE void requestNewInstance(const QModelIndex &index);
    // A group: all its windows
    Q_INVOKABLE void requestClose(const QModelIndex &index);
    Q_INVOKABLE void requestMove(const QModelIndex &index);
    Q_INVOKABLE void requestResize(const QModelIndex &index);
    // A group: when all its windows have the state, it is removed from all, otherwise set on all
    Q_INVOKABLE void requestToggleMinimized(const QModelIndex &index);
    Q_INVOKABLE void requestToggleMaximized(const QModelIndex &index);
    Q_INVOKABLE void requestToggleKeepAbove(const QModelIndex &index);
    Q_INVOKABLE void requestToggleKeepBelow(const QModelIndex &index);
    Q_INVOKABLE void requestToggleFullScreen(const QModelIndex &index);
    Q_INVOKABLE void requestPublishDelegateGeometry(const QModelIndex &index, const QRect &geometry,
                                                    QObject *delegate = nullptr);
    // Moves a top-level row (SortManual and SortDisabled)
    Q_INVOKABLE bool move(int row, int newPos, const QModelIndex &parent = QModelIndex());

    // Maia: starts an application by its launcher URL ("applications:org.kde.konsole.desktop")
    Q_INVOKABLE void launch(const QString &launcherUrl);

Q_SIGNALS:
    void countChanged();
    void groupModeChanged();
    void groupInlineChanged();
    void sortModeChanged();
    void filterSkipTaskbarChanged();
    void anyTaskDemandsAttentionChanged();
    void activeTaskChanged();
    void connectedChanged();

private:
    // A top-level row: one window, or the windows of one application (group)
    struct Row {
        quintptr uid; // stable while the row exists: the internal id of its children
        QString key;
        QStringList windows; // ids, in the order they appeared
    };

    void setSource(WindowSource *source);
    void rebuild();
    bool accepts(const WindowInfo &window) const;
    QString groupKey(const WindowInfo &window) const;

    void insertWindow(const WindowInfo &window);
    void removeWindow(const QString &id);
    void onWindowChanged(const WindowInfo &before, const WindowInfo &after);
    void onIconChanged(const QString &id);
    // Moves rows until they are in the order of the sort mode
    void sortRows();
    bool lessThan(const Row &a, const Row &b) const;
    int rowOfKey(const QString &key) const;
    // Where the window is: row and child (child -1 for a row of one window)
    bool locate(const QString &id, int &row, int &child) const;
    QModelIndex indexOfWindow(const QString &id) const;
    // The windows of a row changed (a group gained or lost one): any of its roles may differ.
    // A change of one window reports only its changed roles instead (onWindowChanged).
    void notifyRowChanged(int row);
    void updateSummary();

    const WindowInfo *windowAt(const QModelIndex &index) const;
    QVariant windowData(const WindowInfo &window, int role) const;
    QVariant groupData(const Row &row, int role) const;
    QIcon iconFor(const WindowInfo &window) const;
    QList<const WindowInfo *> windowsOf(const QModelIndex &index) const;
    void toggleState(const QModelIndex &index, State state);

    QPointer<WindowSource> m_source;
    QList<Row> m_rows;
    quintptr m_nextUid = 1;
    GroupMode m_groupMode = GroupDisabled;
    bool m_groupInline = false;
    SortMode m_sortMode = SortManual;
    bool m_filterSkipTaskbar = true;
    // For the change signals of the summary properties
    bool m_anyDemandsAttention = false;
    QString m_activeWindow;
    mutable QHash<QString, QIcon> m_themeIcons;
};

} // namespace MaiaWindows
