#pragma once

// One Maia Settings window per session: a second start hands its page to the running one (over a
// local socket, $XDG_RUNTIME_DIR/maia/settings-$WAYLAND_DISPLAY.sock) and exits, so "More Wi-Fi
// settings" clicked twice brings the same window forward on the right page.

#include <QObject>

class QLocalServer;

class SingleInstance : public QObject
{
    Q_OBJECT

public:
    explicit SingleInstance(QObject *parent = nullptr);

    // true: this process serves; false: another one runs and got `page` (this one should exit)
    bool claim(const QString &page);

Q_SIGNALS:
    // Another start asked for this page ("" = just show the window)
    void activationRequested(const QString &page);

private:
    static QString socketPath();

    QLocalServer *m_server = nullptr;
};
