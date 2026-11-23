#pragma once

// FullscreenState: whether the window the user works in is fullscreen on a screen (a film, a game,
// a presentation), and which application it is. For a shell that keeps quiet meanwhile, e.g. no
// notification popups.
//
//   FullscreenState { id: fullscreen; screen: popupsWindow.screen }
//   NotificationPopupsModel { suppressed: fullscreen.active }
//
// Derived from what the window service already reports for every window (its states and its
// geometry), nothing new in the contract. The rule: the active window is fullscreen and lies on
// `screen` (its centre); without a screen, on any screen. A fullscreen film on another monitor does
// not count while the user works on this one, and neither does a minimized one.

#include "WindowSource.h"

#include <QObject>
#include <QPointer>
#include <QScreen>
#include <QtQml/qqmlregistration.h>

namespace MaiaWindows {

class FullscreenState : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // The screen that matters (where the shell shows something); null = any screen. An object,
    // because what QML calls a window's screen is not a QScreen but its description (found by name)
    Q_PROPERTY(QObject *screen READ screen WRITE setScreenObject NOTIFY screenChanged)

    Q_PROPERTY(bool active READ active NOTIFY changed)
    // The fullscreen window and its application, "" when none
    Q_PROPERTY(QString windowId READ windowId NOTIFY changed)
    Q_PROPERTY(QString appId READ appId NOTIFY changed)
    Q_PROPERTY(QString appName READ appName NOTIFY changed)

public:
    explicit FullscreenState(QObject *parent = nullptr);
    // For tests: a source other than the service
    FullscreenState(WindowSource *source, QObject *parent);

    QScreen *screen() const { return m_screen; }
    void setScreen(QScreen *screen);
    void setScreenObject(QObject *screen);

    bool active() const { return !m_window.id.isEmpty(); }
    QString windowId() const { return m_window.id; }
    QString appId() const { return m_window.appId; }
    QString appName() const { return m_window.appName; }

Q_SIGNALS:
    void screenChanged();
    void changed();

private:
    void update();
    void windowChanged(const WindowInfo &before, const WindowInfo &after);

    WindowSource *m_source;
    QPointer<QScreen> m_screen;
    QMetaObject::Connection m_screenGeometry;
    // The fullscreen window now (its id empty: none)
    WindowInfo m_window;
};

} // namespace MaiaWindows
