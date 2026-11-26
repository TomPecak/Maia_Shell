#pragma once

// TrayMenu: the menu of an item, while a shell shows it. Data only: the shell draws the entries in
// its own style, as a cascade (Lumen) or a stack of pages (Maia):
//
//   TrayMenu { id: menu; itemId: model.itemId; active: popup.opened; onClosed: popup.close() }
//   ListView { model: menu.entries; delegate: Row { text: model.label; onClicked: menu.trigger(model.entryId, window) } }
//   ListView { model: menu.submenu(entryId) }          // a submenu's entries, kept up to date
//
// While active, the service follows the application's menu; ready turns true with its first
// layout (show the popup then, so it never grows in front of the user). Entries are updated by
// their ids: a changed label changes one row, nothing is reset. A submenu's model is the same
// object as long as the menu is open; call aboutToShow(entryId) when it opens (the application may
// fill it then) and submenuClosed(entryId) when it closes.
//
// closed() comes when the menu cannot stay: its item is gone, the service is away, or a trigger()
// was sent (an entry was picked). active false closes it for the application.

#include "TrayData.h"

#include <QAbstractListModel>
#include <QHash>
#include <QPointer>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

namespace MaiaTray {

class TrayMenuEntriesModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Given by TrayMenu.entries and TrayMenu.submenu()")

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Toggle { NoToggle = 0, Checkmark = 1, Radio = 2 };
    Q_ENUM(Toggle)

    enum Role {
        EntryIdRole = Qt::UserRole + 1,
        SeparatorRole,
        LabelRole,
        EnabledRole,
        IconSourceRole,
        ToggleRole,
        CheckedRole,
        ShortcutRole,
        SubmenuRole,
    };
    Q_ENUM(Role)

    explicit TrayMenuEntriesModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    // To these entries, by their ids
    void update(const MenuEntries &target);

Q_SIGNALS:
    void countChanged();

private:
    static QList<int> changedRoles(const MenuEntryData &before, const MenuEntryData &after);

    MenuEntries m_rows;
};

class TrayMenu : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(uint itemId READ itemId WRITE setItemId NOTIFY itemIdChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    // The entries of the menu itself
    Q_PROPERTY(MaiaTray::TrayMenuEntriesModel *entries READ entries CONSTANT)

public:
    explicit TrayMenu(QObject *parent = nullptr);
    ~TrayMenu() override;

    uint itemId() const { return m_itemId; }
    void setItemId(uint id);
    bool active() const { return m_active; }
    void setActive(bool active);
    bool ready() const { return m_ready; }
    TrayMenuEntriesModel *entries() const { return m_entries; }

    // The entries of a submenu (an empty model while it has none)
    Q_INVOKABLE MaiaTray::TrayMenuEntriesModel *submenu(int entryId);
    Q_INVOKABLE void aboutToShow(int entryId);
    Q_INVOKABLE void submenuClosed(int entryId);
    // The user picked an entry; with the shell's window, the window it raises may come forward.
    // The menu closes.
    Q_INVOKABLE void trigger(int entryId, QWindow *window = nullptr);

    // The children of entry `id` in `entries`, or nullptr
    static const MenuEntries *childrenOf(const MenuEntries &entries, int id);

Q_SIGNALS:
    void itemIdChanged();
    void activeChanged();
    void readyChanged();
    void closed();
    void triggered(int entryId);

private:
    void open();
    void close(bool tellShell);
    void applyLayout(quint64 menu, const MenuEntries &entries);
    void setReady(bool ready);

    uint m_itemId = 0;
    bool m_active = false;
    bool m_ready = false;
    quint64 m_menu = 0;
    MenuEntries m_layout;
    TrayMenuEntriesModel *m_entries;
    QHash<int, TrayMenuEntriesModel *> m_submenus;
};

} // namespace MaiaTray
