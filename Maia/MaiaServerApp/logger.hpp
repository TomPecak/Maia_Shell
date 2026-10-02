#pragma once

#include <QElapsedTimer>
#include <QWebSocket>
#include <QMessageLogContext>
#include <QMutex>
#include <QObject>
#include <QString>
#include <QtMessageHandler>
#include <QQueue>
#include <QFile>
#include <memory>

class Logger : public QObject
{
    Q_OBJECT

public:
    explicit Logger(QObject *parent = nullptr);
    ~Logger();

    void run();
    void stop();
    void uninit();

    // Zmienione: Funkcja wywoływana asynchronicznie (Thread-safe) do wysyłania przez sieć
    Q_INVOKABLE void processQueuedLogs();

private Q_SLOTS:
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
    QString constructServerUrl();
    void sendBufferedLogs();
    void setupFileLogging(); // Zmienione: nowa metoda do plików

private:
    QtMessageHandler originalHandler = nullptr;
    QWebSocket m_socket;
    int reconnect_time = 0;
    QString m_serverUrl;
    static Logger *m_logger;
    QMutex logMutex;
    QElapsedTimer timer;
    qint64 lastLogTime = 0;

    // Plik do logowania
    std::unique_ptr<QFile> m_logFile;

    // Bufor logów dla WebSocketa
    QQueue<QString> m_logBuffer;
    const int MAX_BUFFER_SIZE = 2048;
};
