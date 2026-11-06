#include "AppearanceSource.h"

#include "AppearanceConnection.h"

#include <QCoreApplication>

namespace MaiaAppearance {

namespace {
AppearanceSource *s_instance = nullptr;
}

AppearanceSource::AppearanceSource(QObject *parent)
    : QObject(parent)
{
}

AppearanceSource *AppearanceSource::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new AppearanceConnection(AppearanceConnection::defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

void AppearanceSource::setInstance(AppearanceSource *source)
{
    s_instance = source;
}

Result AppearanceSource::unavailable()
{
    return Result{Appearance::ErrorCode::Unavailable, QStringLiteral("the appearance service is not running")};
}

const ThemeData *AppearanceSource::theme(const QString &id) const
{
    for (const auto &theme : m_themes) {
        if (theme.id == id)
            return &theme;
    }
    return nullptr;
}

void AppearanceSource::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    if (!connected) {
        // Nothing is known without the service
        applyThemes({});
        applyCurrent({});
        applyCapabilities({});
    }
    Q_EMIT connectedChanged();
}

void AppearanceSource::applyCapabilities(const CapabilitiesData &capabilities)
{
    if (m_capabilities == capabilities)
        return;
    m_capabilities = capabilities;
    Q_EMIT capabilitiesChanged();
}

void AppearanceSource::applyThemes(const QList<ThemeData> &themes)
{
    if (m_themes == themes)
        return;
    m_themes = themes;
    Q_EMIT themesChanged();
}

void AppearanceSource::applyCurrent(const CurrentData &current)
{
    if (m_current == current)
        return;
    m_current = current;
    Q_EMIT currentChanged();
}

} // namespace MaiaAppearance
