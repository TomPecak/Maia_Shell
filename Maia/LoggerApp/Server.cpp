#include "Server.hpp"

#include <QDebug>

Server::Server(QObject *parent)
    : QObject(parent)
    , m_server("LoggerServer", QWebSocketServer::NonSecureMode, this)
    , m_nextClientId(1)
{
    connect(&m_server, &QWebSocketServer::newConnection, this, &Server::handleNewConnection);
}

Server::~Server()
{
    for (QWebSocket *client : m_clients) {
        client->deleteLater();
    }
}

bool Server::startServer(int port)
{
    if (!m_server.listen(QHostAddress::Any, port)) {
        qDebug() << "[ERROR] Failed to start WebSocket server on port" << port;
        return false;
    }
    qDebug() << "[INFO] Logger Server started listening on port:" << port;
    return true;
}

void Server::handleNewConnection()
{
    qDebug() << "[INFO] Logger Server: new connection";
    while (m_server.hasPendingConnections()) {
        QWebSocket *client = m_server.nextPendingConnection();
        m_clients.append(client);
        m_clientIds.insert(client, m_nextClientId++);

        connect(client, &QWebSocket::disconnected, this, &Server::handleClientDisconnected);
        connect(client, &QWebSocket::textMessageReceived, this, &Server::handleTextMessageReceived);
    }
}

void Server::handleClientDisconnected()
{
    QWebSocket *clientSocket = qobject_cast<QWebSocket *>(sender());
    if (clientSocket) {
        m_clients.removeAll(clientSocket);
        m_clientIds.remove(clientSocket);
        clientSocket->deleteLater();
        qDebug() << "[INFO] Logger Server: client disconnected.";
    }
}

void Server::handleTextMessageReceived(const QString &message)
{
    QWebSocket *clientSocket = qobject_cast<QWebSocket *>(sender());
    if (clientSocket) {
        int clientId = m_clientIds.value(clientSocket, 0);
        emit messageReceived(clientId, clientSocket, message);
    }
}
