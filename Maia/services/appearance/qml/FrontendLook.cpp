#include "FrontendLook.h"

#include "AppearanceSource.h"

namespace MaiaAppearance {

namespace {
int s_nextHandle = 1;
}

FrontendLook::FrontendLook(QObject *parent)
    : QObject(parent)
    , m_source(AppearanceSource::instance())
    , m_handle(s_nextHandle++)
{
}

FrontendLook::~FrontendLook()
{
    if (m_active)
        m_source->deactivateFrontend(m_handle);
}

void FrontendLook::setFrontend(const QString &frontend)
{
    if (m_frontend == frontend)
        return;
    m_frontend = frontend;
    Q_EMIT frontendChanged();
    update();
}

void FrontendLook::setWindowDecoration(const QString &themeId)
{
    if (m_windowDecoration == themeId)
        return;
    m_windowDecoration = themeId;
    Q_EMIT windowDecorationChanged();
    update();
}

void FrontendLook::componentComplete()
{
    m_complete = true;
    update();
}

void FrontendLook::update()
{
    // Activated once all properties are set (not once per property)
    if (!m_complete)
        return;
    if (m_active)
        m_source->deactivateFrontend(m_handle);
    m_active = !m_frontend.isEmpty();
    if (m_active)
        m_source->activateFrontend(m_handle, m_frontend, m_windowDecoration);
}

} // namespace MaiaAppearance
