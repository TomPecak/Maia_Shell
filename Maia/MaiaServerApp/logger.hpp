#pragma once

#include <QElapsedTimer>
#include <QLocalSocket>
#include <QMessageLogContext>
#include <QMutex>
#include <QObject>
#include <QString>
#include <QtMessageHandler>

class Logger : public QObject
{
    Q_OBJECT

    enum class CommandSend : uint8_t { LOG = 0x01 };

public:
    explicit Logger(QObject *parent = nullptr);
    ~Logger();

    void run();
    void stop();

    void uninit();

private slots:
    void onSocketConnected();
    void onSocketDisconnected();
    void onSocketReadyRead();
    void onSocketError(QLocalSocket::LocalSocketError socketError);

private:
    static void messageHandler(QtMsgType type,
                               const QMessageLogContext &context,
                               const QString &msg);
    void init();
    void setOriginalHandler(QtMessageHandler handler);
    void connectToServer(const QString &serverName);
    void sendLog(const QString message);

private:
    QtMessageHandler originalHandler = nullptr;
    QLocalSocket m_socket;
    int reconnect_time = 0;
    quint32 m_nextBlockSize = 0;
    QString m_serverName;
    static Logger *m_logger;
    QMutex logMutex;
    QElapsedTimer timer;
    qint64 lastLogTime = 0;
};
