#include "ProxyWindowServer.hpp"

#include <QDataStream>
#include <QLocalSocket>

ProxyWindowLocalServer::ProxyWindowLocalServer(QObject *parent)
    : QObject(parent)
{
    connect(&m_server,
            &QLocalServer::newConnection,
            this,
            &ProxyWindowLocalServer::handleNewConnection);
}

ProxyWindowLocalServer::~ProxyWindowLocalServer() {}

void ProxyWindowLocalServer::installWindow(QQmlApplicationEngine &engine)
{
    if (engine.rootObjects().isEmpty()) {
        qDebug() << "No root objects available to set geometry.";
        return;
    }

    QObject *rootObject = engine.rootObjects().first();
    QQuickWindow *window = qobject_cast<QQuickWindow *>(rootObject);

    if (!window) {
        qDebug() << "Root object is not a QQuickWindow!";
        return;
    }

    m_window = window;

    connect(m_window,
            &QQuickWindow::visibleChanged,
            this,
            &ProxyWindowLocalServer::onWindowVisibleChanged);
}

bool ProxyWindowLocalServer::startServer(const QString &proxyWindowAddress)
{
    QLocalServer::removeServer(proxyWindowAddress);
    if (!m_server.listen(proxyWindowAddress)) {
        qDebug() << "[ERROR] Failed to start Proxy Window Local Socket Server";
        return false;
    }
    return true;
}

void ProxyWindowLocalServer::handleNewConnection()
{
    while (m_server.hasPendingConnections()) {
        QLocalSocket *client = m_server.nextPendingConnection();
        m_clients.append(client);
        m_clientBlockSizes.insert(client, 0);

        connect(client,
                &QLocalSocket::disconnected,
                this,
                &ProxyWindowLocalServer::handleClientDisconnected);
        connect(client,
                &QLocalSocket::readyRead,
                this,
                &ProxyWindowLocalServer::handleClientReadyRead);

        if (m_window) {
            updateVisibleState(client, m_window->isVisible());
        }
    }
}

void ProxyWindowLocalServer::handleClientDisconnected()
{
    QLocalSocket *clientSocket = qobject_cast<QLocalSocket *>(sender());
    if (clientSocket) {
        m_clients.removeAll(clientSocket);
        m_clientBlockSizes.remove(clientSocket);
        clientSocket->deleteLater();
    }
}

void ProxyWindowLocalServer::handleClientReadyRead()
{
    QLocalSocket *clientSocket = qobject_cast<QLocalSocket *>(sender());
    if (clientSocket) {
        parseCommand(clientSocket);
    }
}

void ProxyWindowLocalServer::parseCommand(QLocalSocket *clientSocket)
{
    QDataStream in(clientSocket);

    quint32 &nextBlockSize = m_clientBlockSizes[clientSocket];

    forever {
        if (nextBlockSize == 0) {
            if (clientSocket->bytesAvailable() < (int) sizeof(quint32))
                break;
            in >> nextBlockSize;
        }

        if (clientSocket->bytesAvailable() < nextBlockSize)
            break;

        // We have the entire command
        quint8 commandRaw;
        in >> commandRaw;

        qDebug() << "Proxy Window Command = " << commandRaw;
        auto command = static_cast<CommandReceived>(commandRaw);

        if (command == CommandReceived::SET_VISIBLE) {
            bool requestedVisible;
            in >> requestedVisible;
            qDebug() << "Server: Received SetVisible command, visible:" << requestedVisible;
            if (!m_window)
                continue;

            if (m_window->isVisible() != requestedVisible) {
                m_window->setVisible(requestedVisible);
                // Visibility change will trigger onWindowVisibleChanged,
                // which will broadcast the state to all clients.
            }
        } else if (command == CommandReceived::QUIT_PROCESS) {

        } else {
            qDebug() << "[ERROR] ProxyWindowLocalServer: Received unknown command type:" << commandRaw;
        }

        nextBlockSize = 0; // Ready for the next command
    }
}

void ProxyWindowLocalServer::onWindowVisibleChanged(bool visible)
{
    if (!m_window) {
        return;
    }

    broadcastVisibleState(m_window->isVisible());
}

void ProxyWindowLocalServer::broadcastVisibleState(bool visible)
{
    QByteArray block;

    prepareVisibleFrame(block, visible);

    for (QLocalSocket *client : m_clients) {
        client->write(block);
        client->flush();
    }
}

void ProxyWindowLocalServer::updateVisibleState(QLocalSocket *client, bool visible)
{
    QByteArray block;

    prepareVisibleFrame(block, visible);

    client->write(block);
    client->flush();
}

void ProxyWindowLocalServer::prepareVisibleFrame(QByteArray &block, bool visible)
{
    QDataStream out(&block, QIODevice::WriteOnly);

    out << (quint32) 0; // Reserve space for size
    out << static_cast<uint8_t>(CommandSent::SET_VISIBLE);
    out << visible;
    out.device()->seek(0);
    out << (quint32) (block.size() - sizeof(quint32));
}
