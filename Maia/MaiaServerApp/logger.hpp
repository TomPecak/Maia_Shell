#pragma once

#include <QElapsedTimer>
#include <QWebSocket>
#include <QMessageLogContext>
#include <QMutex>
#include <QObject>
#include <QString>
#include <QtMessageHandler>
#include <QQueue>

class Logger : public QObject
{
    Q_OBJECT

public:
    explicit Logger(QObject *parent = nullptr);
    ~Logger();

    void run();
    void stop();

    void uninit();

private slots:
    void onSocketConnected();
    void onSocketDisconnected();
    void onSocketError(QAbstractSocket::SocketError socketError);
    void onTextMessageReceived(const QString &message);

private:
    static void messageHandler(QtMsgType type,
                               const QMessageLogContext &context,
                               const QString &msg);
    void init();
    void setOriginalHandler(QtMessageHandler handler);
    void connectToServer(const QString &serverUrl);
    void sendLog(const QString message);
    QString constructServerUrl();
    void sendBufferedLogs();

private:
    QtMessageHandler originalHandler = nullptr;
    QWebSocket m_socket;
    int reconnect_time = 0;
    QString m_serverUrl;
    static Logger *m_logger;
    QMutex logMutex;
    QElapsedTimer timer;
    qint64 lastLogTime = 0;

    //buffer
    QQueue<QString> m_logBuffer;
    const int MAX_BUFFER_SIZE = 2048;
};
