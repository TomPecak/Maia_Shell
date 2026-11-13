#include "FullscreenState.h"

#include "ServiceConnection.h"

namespace MaiaWindows {

FullscreenState::FullscreenState(QObject *parent)
    : FullscreenState(nullptr, parent)
{
}

FullscreenState::FullscreenState(WindowSource *source, QObject *parent)
    : QObject(parent)
    , m_source(source ? source : ServiceConnection::instance())
{
    connect(m_source, &WindowSource::windowAdded, this, &FullscreenState::update);
    connect(m_source, &WindowSource::windowRemoved, this, &FullscreenState::update);
    connect(m_source, &WindowSource::windowChanged, this, &FullscreenState::windowChanged);
    update();
}

void FullscreenState::setScreen(QScreen *screen)
{
    if (m_screen == screen)
        return;
    disconnect(m_screenGeometry);
    m_screen = screen;
    if (screen)
        m_screenGeometry = connect(screen, &QScreen::geometryChanged, this, &FullscreenState::update);
    Q_EMIT screenChanged();
    update();
}

void FullscreenState::windowChanged(const WindowInfo &before, const WindowInfo &after)
{
    // A window being dragged changes on every frame: only what the rule reads matters
    constexpr quint32 relevant = Active | Minimized | Fullscreen;
    if ((before.states & relevant) == (after.states & relevant) && before.geometry == after.geometry
        && before.appName == after.appName && before.appId == after.appId)
        return;
    update();
}

void FullscreenState::update()
{
    // The active window: the most recently activated one with the flag (a compositor may briefly
    // report two while focus moves)
    const WindowInfo *active = nullptr;
    for (const WindowInfo &w : m_source->windows()) {
        if (w.has(Active) && !w.has(Minimized) && (!active || w.lastActivated > active->lastActivated))
            active = &w;
    }
    WindowInfo found;
    if (active && active->has(Fullscreen)) {
        const bool here = !m_screen || m_screen->geometry().contains(active->geometry.center());
        if (here)
            found = *active;
    }
    if (found.id == m_window.id && found.appId == m_window.appId && found.appName == m_window.appName)
        return;
    m_window = found;
    Q_EMIT changed();
}

} // namespace MaiaWindows
