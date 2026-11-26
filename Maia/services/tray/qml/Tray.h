#pragma once

// Tray: the system tray of the session, for shells (Maia.Tray). Data and requests only; the shell
// draws the items (TrayItemsModel) and their menus (TrayMenu) in its own style.
//
//   import Maia.Tray
//   TrayItemsModel { id: items }
//   MouseArea {
//       onClicked: model.itemIsMenu ? openMenu() : Tray.activate(model.itemId, 0, 0, window)
//   }
//
// What a click does is the shell's choice, the usual one: primary → activate() (or the menu, for
// an item that is only a menu: itemIsMenu), secondary or long press → TrayMenu (or contextMenu()
// for an item without one: hasMenu false), middle → secondaryActivate(), wheel → scroll().
//
// With the shell's window, activate() asks the compositor for an xdg-activation token first (at
// most 300 ms), so that the application may raise its window on Wayland.

#include <QObject>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

#include <functional>

namespace MaiaTray {

class Tray : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // All items, and those that need attention
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int attentionCount READ attentionCount NOTIFY attentionCountChanged)

public:
    // The numbers of the roles status and category of TrayItemsModel
    enum Status { Passive = 0, Active = 1, NeedsAttention = 2 };
    Q_ENUM(Status)
    enum Category { ApplicationStatus = 0, Communications = 1, SystemServices = 2, Hardware = 3 };
    Q_ENUM(Category)

    explicit Tray(QObject *parent = nullptr);

    bool connected() const;
    int count() const;
    int attentionCount() const { return m_attentionCount; }

    // x, y: where, in global coordinates, when the shell knows (Wayland applications ignore them)
    Q_INVOKABLE void activate(uint itemId, int x = 0, int y = 0, QWindow *window = nullptr);
    Q_INVOKABLE void secondaryActivate(uint itemId, int x = 0, int y = 0, QWindow *window = nullptr);
    Q_INVOKABLE void contextMenu(uint itemId, int x = 0, int y = 0);
    // delta: 120 a notch of the wheel
    Q_INVOKABLE void scroll(uint itemId, int delta, bool horizontal = false);

    // Calls `send` with an xdg-activation token for `window` (on Wayland, at most 300 ms later), or
    // with "" at once without a window
    static void withToken(QWindow *window, const QString &appId, std::function<void(const QString &)> send);

Q_SIGNALS:
    void connectedChanged();
    void countChanged();
    void attentionCountChanged();

private:
    void recount();

    int m_count = 0;
    int m_attentionCount = 0;
};

} // namespace MaiaTray
