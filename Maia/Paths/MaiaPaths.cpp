#include "MaiaPaths.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QStandardPaths>

namespace MaiaPaths
{
QString version()
{
    return QStringLiteral(MAIA_VERSION_STRING);
}

QString configDir()
{
    // GenericConfigLocation is $XDG_CONFIG_HOME, or ~/.config
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/maia/") + version();
    QDir().mkpath(dir);
    return dir;
}

QString configFile(const QString &name)
{
    return configDir() + QLatin1Char('/') + name;
}

void setupApplicationNames()
{
    QCoreApplication::setOrganizationName(QStringLiteral("maia/") + version());
    QCoreApplication::setApplicationName(QStringLiteral("maia"));
}
} // namespace MaiaPaths
