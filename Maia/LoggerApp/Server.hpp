#pragma once

#include <QObject>
#include <QList>
#include <QWebSocketServer>
#include <QWebSocket>

class Server : public QObject
{
    Q_OBJECT

public:
    explicit Server(QObject *parent = nullptr);
    ~Server();

    bool startServer(int port);

signals:
    void messageReceived(int clientId, QWebSocket *socket, QString message);

private slots:
    void handleNewConnection();
    void handleClientDisconnected();
    void handleTextMessageReceived(const QString &message);

private:
    QWebSocketServer m_server;
    QList<QWebSocket *> m_clients;
    QHash<QWebSocket *, int> m_clientIds;
    int m_nextClientId;
};
