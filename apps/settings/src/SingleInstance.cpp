#include "SingleInstance.h"

#include <QDir>
#include <QLocalServer>
#include <QLocalSocket>
#include <QStandardPaths>

SingleInstance::SingleInstance(QObject *parent)
    : QObject(parent)
{
}

QString SingleInstance::socketPath()
{
    QString runtime = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    QString display = qEnvironmentVariable("WAYLAND_DISPLAY", qEnvironmentVariable("DISPLAY", QStringLiteral("default")));
    display.replace(QLatin1Char('/'), QLatin1Char('_'));
    QDir().mkpath(runtime + QStringLiteral("/maia"));
    return runtime + QStringLiteral("/maia/settings-") + display + QStringLiteral(".sock");
}

bool SingleInstance::claim(const QString &page)
{
    const QString path = socketPath();
    QLocalSocket socket;
    socket.connectToServer(path);
    if (socket.waitForConnected(300)) {
        socket.write(page.toUtf8() + '\n');
        socket.waitForBytesWritten(300);
        socket.disconnectFromServer();
        return false;
    }
    // Nobody answers: a socket left by a crash
    QLocalServer::removeServer(path);
    m_server = new QLocalServer(this);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server->listen(path)) {
        qWarning() << "[Maia Settings] cannot listen on" << path << m_server->errorString();
        return true;
    }
    connect(m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *client = m_server->nextPendingConnection()) {
            connect(client, &QLocalSocket::readyRead, this, [this, client] {
                if (!client->canReadLine())
                    return;
                Q_EMIT activationRequested(QString::fromUtf8(client->readLine().trimmed()));
                client->disconnectFromServer();
            });
            connect(client, &QLocalSocket::disconnected, client, &QObject::deleteLater);
        }
    });
    return true;
}
