#pragma once

// The connection of a shell to the TrayHost of the tray service. One per process (instance()),
// shared by Tray, TrayItemsModel and TrayMenu.
//
// The service sends all items first, then batches of changes (at most one per frame); a batch is
// read into Qt values in the KJ thread and applied in the GUI thread as a whole: the models update
// once per batch. The last items stay while the service is away (connected is false), so a restart
// of the service does not empty the tray for a moment.
//
// Open menus: openMenu() gives a number; the menu's layouts come with menuLayout(number, …) until
// closeMenu(number), or menuClosed(number) when the item went away or the connection ended.
//
// Socket: $MAIA_TRAY_SOCKET, or $XDG_RUNTIME_DIR/maia/tray-$WAYLAND_DISPLAY.sock

#include "ServiceLink.h"
#include "TrayData.h"

#include "tray.capnp.h"

#include <QHash>
#include <QList>

#include <map>
#include <optional>

namespace MaiaTray {

class TrayConnection final : public ServiceLink
{
    Q_OBJECT

public:
    explicit TrayConnection(const QString &socketPath, QObject *parent = nullptr);
    ~TrayConnection() override;

    static TrayConnection *instance();
    static QString defaultSocketPath();

    // The items by id (the snapshot and every batch since)
    const QHash<quint32, ItemData> &items() const { return m_items; }
    const ItemData *find(quint32 id) const;

    // Requests; failures only go to the log (the item was gone, the service away)
    void activate(quint32 id, int x, int y, const QString &activationToken);
    void secondaryActivate(quint32 id, int x, int y, const QString &activationToken);
    void contextMenu(quint32 id, int x, int y);
    void scroll(quint32 id, int delta, bool horizontal);

    // A menu of item `id`; 0 when there is no connection (nothing will come)
    quint64 openMenu(quint32 id);
    void closeMenu(quint64 menu);
    void menuAboutToShow(quint64 menu, int entryId);
    void menuSubmenuClosed(quint64 menu, int entryId);
    void menuActivate(quint64 menu, int entryId, const QString &activationToken);

Q_SIGNALS:
    // All items again (a new connection)
    void reset();
    // One batch: new or changed items, and removed ids
    void batch(const QList<MaiaTray::ItemData> &changed, const QList<quint32> &removed);
    void menuLayout(quint64 menu, const MaiaTray::MenuEntries &entries);
    void menuClosed(quint64 menu);

protected:
    void connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks) override;
    void disconnected() override;

private:
    friend class ShellListener;
    friend class MenuListener;

    // GUI thread
    void applySnapshot(const QList<ItemData> &items);
    void applyBatch(const QList<ItemData> &changed, const QList<quint32> &removed);
    void click(const char *what, quint32 id, int x, int y, const QString &activationToken, bool secondary);

    QHash<quint32, ItemData> m_items;
    // Menus the GUI thread has open (their numbers), told closed when the connection ends
    QList<quint64> m_openMenus;
    quint64 m_nextMenu = 0;

    // KJ thread
    std::optional<Contract::TrayHost::Client> m_host;
    std::optional<Contract::Subscription::Client> m_subscription;
    std::map<quint64, Contract::Menu::Client> m_menus;
};

} // namespace MaiaTray
