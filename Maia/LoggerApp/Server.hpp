#pragma once

#include <QList>
#include <QLocalServer>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

class Server : public QObject
{
    Q_OBJECT

    enum class CommandSent : uint8_t {
        SET_VISIBLE = 0x01,
    };

    enum class CommandReceived : uint8_t { LOG = 0x01 };

public:
    explicit Server(QObject *parent = nullptr);
    ~Server();

    bool startServer(const QString &proxyWindowAddress);

signals:
    void messageReceived(int clientId, QLocalSocket *socket, QString message);

private slots:
    void handleNewConnection();
    void handleClientDisconnected();
    void handleClientReadyRead();

private:
    void parseCommand(QLocalSocket *clientSocket);

    QLocalServer m_server;
    QList<QLocalSocket *> m_clients;
    QHash<QLocalSocket *, quint32> m_clientBlockSizes;
    QHash<QLocalSocket *, int> m_clientIds;
    int m_nextClientId;
};
