#include "Server.hpp"

#include <QDataStream>
#include <QLocalSocket>

Server::Server(QObject *parent)
    : QObject(parent)
    , m_nextClientId(1)
{
    connect(&m_server, &QLocalServer::newConnection, this, &Server::handleNewConnection);
}

Server::~Server() {}

bool Server::startServer(const QString &localAddress)
{
    QLocalServer::removeServer(localAddress);
    if (!m_server.listen(localAddress)) {
        qDebug() << "[ERROR] Failed to start LoggerServer Local Socket Server";
        return false;
    }
    qDebug() << "[INFO] LoggerServer start listening on address: " << localAddress;
    return true;
}

void Server::handleNewConnection()
{
    qDebug() << "[INFO] LoggerServer handle new connection";
    while (m_server.hasPendingConnections()) {
        QLocalSocket *client = m_server.nextPendingConnection();
        m_clients.append(client);
        m_clientBlockSizes.insert(client, 0);
        m_clientIds.insert(client, m_nextClientId++);

        connect(client, &QLocalSocket::disconnected, this, &Server::handleClientDisconnected);
        connect(client, &QLocalSocket::readyRead, this, &Server::handleClientReadyRead);
    }
}

void Server::handleClientDisconnected()
{
    QLocalSocket *clientSocket = qobject_cast<QLocalSocket *>(sender());
    if (clientSocket) {
        m_clients.removeAll(clientSocket);
        m_clientBlockSizes.remove(clientSocket);
        clientSocket->deleteLater();
        qDebug() << "[INFO] LoggerServer: Client disconnected.";
    }
}

void Server::handleClientReadyRead()
{
    QLocalSocket *clientSocket = qobject_cast<QLocalSocket *>(sender());
    if (clientSocket) {
        parseCommand(clientSocket);
    }
}

void Server::parseCommand(QLocalSocket *clientSocket)
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

        // Mamy całą komendę
        quint8 commandRaw;
        in >> commandRaw;

        auto command = static_cast<CommandReceived>(commandRaw);

        if (command == CommandReceived::LOG) {
            QString message;
            in >> message;
            int clientId = m_clientIds.value(clientSocket, 0);
            emit messageReceived(clientId, clientSocket, message);
        } else {
            qDebug() << "[ERROR] LoggerServer: Received unknown command type:" << commandRaw;
        }

        nextBlockSize = 0; // Gotowi na następną komendę
    }
}
