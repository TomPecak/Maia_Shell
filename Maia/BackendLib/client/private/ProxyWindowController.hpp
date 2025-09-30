#pragma once

#include <QLocalSocket>
#include <QObject>

class ProxyWindowController : public QObject
{
    Q_OBJECT

    enum class CommandReceived : uint8_t {
        SET_VISIBLE = 0x01,
    };

    enum class CommandSend : uint8_t { SET_VISIBLE = 0x01, QUIT_PROCESS = 0x02 };

public:
    explicit ProxyWindowController(QObject *parent = nullptr);
    ~ProxyWindowController();

    void setVisible(bool visible);
    void quitRemoteProcess();

    void connectToServer(const QString &serverName);

signals:
    void visibleReceived(bool visible);
    void proxyWindowConnected();

private slots:
    void onSocketConnected();
    void onSocketDisconnected();
    void onSocketReadyRead();
    void onSocketError(QLocalSocket::LocalSocketError socketError);

private:
    QLocalSocket m_socket;
    QString m_serverName;
    int reconnect_time = 0;
    quint32 m_nextBlockSize = 0;
    void handleStateUpdate(QDataStream &stream);
    void sendSetVisible(bool visible);
};
