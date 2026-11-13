#include "Sounds.h"

#include "CanberraPlayer.h"

#include <QCoreApplication>
#include <QPointer>
#include <QSettings>
#include <QStandardPaths>

namespace MaiaSounds {

namespace {
QPointer<SoundPlayer> s_player;
}

SoundPlayer *Sounds::player()
{
    if (!s_player) {
        // One per process, lives as long as the application; its thread ends with it
        s_player = new CanberraPlayer(QCoreApplication::instance());
    }
    return s_player;
}

void Sounds::setPlayer(SoundPlayer *player)
{
    s_player = player;
}

QString Sounds::defaultTheme()
{
    const QString kdeglobals = QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("kdeglobals"));
    if (!kdeglobals.isEmpty()) {
        const QSettings settings(kdeglobals, QSettings::IniFormat);
        const QString theme = settings.value(QStringLiteral("Sounds/Theme")).toString();
        if (!theme.isEmpty())
            return theme;
    }
    return QStringLiteral("ocean");
}

Sounds::Sounds(QObject *parent)
    : QObject(parent)
    , m_theme(defaultTheme())
{
    connect(player(), &SoundPlayer::availableChanged, this, &Sounds::availableChanged);
}

bool Sounds::available() const
{
    return player()->isAvailable();
}

void Sounds::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    Q_EMIT enabledChanged();
}

void Sounds::setTheme(const QString &theme)
{
    const QString value = theme.isEmpty() ? defaultTheme() : theme;
    if (m_theme == value)
        return;
    m_theme = value;
    Q_EMIT themeChanged();
}

void Sounds::play(const QString &name, const QString &file)
{
    if (!m_enabled)
        return;
    const QUrl url(file);
    const QString path = file.isEmpty() ? QString() : url.isLocalFile() ? url.toLocalFile() : (url.scheme().isEmpty() ? file : QString());
    if (name.isEmpty() && path.isEmpty())
        return;
    // The same sound right again (a burst): once is enough
    const QString key = name + QLatin1Char('\n') + path;
    auto last = m_lastPlayed.find(key);
    if (last != m_lastPlayed.end() && last->isValid() && last->elapsed() < kRepeatGap)
        return;
    if (m_lastPlayed.size() > 64)
        m_lastPlayed.clear();
    m_lastPlayed[key].start();
    player()->play({name, path, m_theme});
}

} // namespace MaiaSounds
