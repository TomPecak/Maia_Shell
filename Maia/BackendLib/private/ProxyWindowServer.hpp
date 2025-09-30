#pragma once

#include <QList>
#include <QLocalServer>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

class ProxyWindowLocalServer : public QObject
{
    Q_OBJECT

    enum class CommandSent : uint8_t {
        SET_VISIBLE = 0x01,
    };

    enum class CommandReceived : uint8_t { SET_VISIBLE = 0x01, QUIT_PROCESS = 0x02 };

public:
    explicit ProxyWindowLocalServer(QObject *parent = nullptr);
    ~ProxyWindowLocalServer();

    void installWindow(QQmlApplicationEngine &engine);
    bool startServer(const QString &proxyWindowAddress);

private slots:
    void handleNewConnection();
    void handleClientDisconnected();
    void handleClientReadyRead();

private:
    void broadcastVisibleState(bool visible);
    void updateVisibleState(QLocalSocket *client, bool visible);
    void prepareVisibleFrame(QByteArray &block, bool visible);
    void parseCommand(QLocalSocket *clientSocket);
    void onWindowVisibleChanged(bool visible);

    QQuickWindow *m_window = nullptr;
    QLocalServer m_server;
    QList<QLocalSocket *> m_clients;
    QHash<QLocalSocket *, quint32> m_clientBlockSizes;
};
