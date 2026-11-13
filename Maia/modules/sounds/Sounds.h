#pragma once

// Sounds: short event sounds of a shell or an app (a notification, a change of the volume, an
// error), a singleton.
//
//   import Maia.Sounds
//   Sounds.play("message-new-instant", "")        // a name of the sound theme
//   Sounds.play("", "file:///…/ding.oga")         // a sender's own file
//
// A name means what happened ("a new message"); how it sounds is the sound theme's: `theme`, by
// default the one of the desktop's settings (kdeglobals [Sounds] Theme), else "ocean"; names it
// lacks come from its fallbacks and "freedesktop". Nothing waits: play() queues the request for the
// player's own thread. The same sound asked for again within kRepeatGap plays once (a flood of
// notifications is one sound, not a hundred). No look, no decisions about when: the shell or the
// app calls play() when something happens.

#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

namespace MaiaSounds {

class SoundPlayer;

class Sounds : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Off: play() does nothing (the shell's "mute event sounds")
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY themeChanged)
    // Sounds can be played at all (the player's library and the sound server are there)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit Sounds(QObject *parent = nullptr);

    static constexpr int kRepeatGap = 150;

    // name: of the sound theme; file: a local file (URL or path); either may be empty
    Q_INVOKABLE void play(const QString &name, const QString &file = QString());

    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    QString theme() const { return m_theme; }
    void setTheme(const QString &theme);
    bool available() const;

    // The theme of the desktop's settings, "ocean" without one
    static QString defaultTheme();
    // For tests: the player every Sounds uses (null: libcanberra); the caller keeps it
    static void setPlayer(SoundPlayer *player);

Q_SIGNALS:
    void enabledChanged();
    void themeChanged();
    void availableChanged();

private:
    static SoundPlayer *player();

    bool m_enabled = true;
    QString m_theme;
    QHash<QString, QElapsedTimer> m_lastPlayed;
};

} // namespace MaiaSounds
