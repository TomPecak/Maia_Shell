#include "logger.hpp"

#include <QDebug>
#include <QMutex>
#include <QMutexLocker>
#include <QTextStream>
#include <QTimer>
#include <QtMessageHandler>
#include <QAbstractSocket>

Logger *Logger::m_logger = nullptr;

void Logger::setOriginalHandler(QtMessageHandler handler)
{
    originalHandler = handler;
}

Logger::Logger(QObject *parent)
    : QObject(parent)
{
#warning "Check whether the Logger class correctly implements the multithreading model"
    m_logger = this;
    init();
}

Logger::~Logger()
{
    uninit();
}

void Logger::init()
{
    connect(&m_socket, &QWebSocket::connected, this, &Logger::onSocketConnected);
    connect(&m_socket, &QWebSocket::disconnected, this, &Logger::onSocketDisconnected);
    connect(&m_socket, &QWebSocket::textMessageReceived, this, &Logger::onTextMessageReceived);
    connect(&m_socket, &QWebSocket::errorOccurred, this, &Logger::onSocketError);
}

QString Logger::constructServerUrl()
{
    // Get host from environment variable or use localhost as fallback
    QString host = qEnvironmentVariable("MAIA_LOG_HOST", "localhost");


    // Get log port from environment variable
    int logPort = 50000;
    if (!qEnvironmentVariableIsEmpty("MAIA_LOG_PORT")) {
        bool ok;
        logPort = qEnvironmentVariable("MAIA_LOG_PORT").toInt(&ok);
        if (!ok) {
            qDebug() << "Failed to convert MAIA_LOG_PORT to a number, using default value 50000";
            logPort = 50000; // Default to 50000 if conversion fails
        }
    }

    // Construct WebSocket URL
    return QString("ws://%1:%2").arg(host).arg(logPort);
}

void Logger::sendBufferedLogs()
{
    QMutexLocker locker(&logMutex);

    if (m_socket.isValid() && (m_socket.state() == QAbstractSocket::ConnectedState)) {
        while (!m_logBuffer.isEmpty()) {
            QString log = m_logBuffer.dequeue();
            m_socket.sendTextMessage(log);
        }
    }
}

void Logger::run()
{
    // Construct WebSocket URL and connect
    connectToServer(constructServerUrl());

    auto originalHandler = qInstallMessageHandler(Logger::messageHandler);
    setOriginalHandler(originalHandler);
}

void Logger::stop()
{
    QMutexLocker locker(&logMutex); // Ensure thread safety

    // Restore original message handler
    if (originalHandler) {
        qInstallMessageHandler(originalHandler);
        originalHandler = nullptr;
    }

    // Close WebSocket
    if (m_socket.isValid()) {
        m_socket.close();
    }

    // Reset internal state
    reconnect_time = 0;
    m_serverUrl.clear();
    m_logger = nullptr;
}

void Logger::onSocketConnected()
{
    qDebug() << "[OK] Connected to Logger server";
    reconnect_time = 0;
    sendBufferedLogs();
}

void Logger::onTextMessageReceived(const QString &message)
{
    qDebug() << "[INFO] Received text message from server:" << message;
    // Currently, the client does not expect server responses.
    // Add processing logic if the server sends responses.
}

void Logger::onSocketError(QAbstractSocket::SocketError socketError)
{
    qDebug() << "[ERROR] WebSocket error:" << socketError << " " << m_socket.errorString();

    m_socket.close();

    reconnect_time = qMin(reconnect_time + 1000, 5000); // Increase reconnect delay, max 5s
    qDebug() << "[INFO] Logger: reconnect time = " << reconnect_time << "ms";
    QTimer::singleShot(reconnect_time, this, [this]() { connectToServer(m_serverUrl); });
}

void Logger::connectToServer(const QString &serverUrl)
{
    if (m_socket.isValid()) {
        qDebug() << "[ERROR] WebSocket already connected or in the process of connecting";
        return;
    }
    m_serverUrl = serverUrl;
    qDebug() << "[INFO] Logger: Attempting to connect to" << m_serverUrl;
    m_socket.open(QUrl(serverUrl));
}

void Logger::sendLog(const QString message)
{
    if (m_socket.isValid() && (m_socket.state() == QAbstractSocket::ConnectedState)) {
        m_socket.sendTextMessage(message);
    } else {
        if (m_logBuffer.size() >= MAX_BUFFER_SIZE) {
            m_logBuffer.dequeue();
        }
        m_logBuffer.enqueue(message);
    }
}

void Logger::onSocketDisconnected()
{
    qDebug() << "[INFO] Disconnected from Logger server";
    // Optionally: trigger reconnection attempt
    reconnect_time = qMin(reconnect_time + 1000, 5000);
    QTimer::singleShot(reconnect_time, this, [this]() { connectToServer(m_serverUrl); });
}

void Logger::messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    if (!m_logger) {
        return;
    }

    QMutexLocker locker(&m_logger->logMutex);

    if (!m_logger->timer.isValid()) {
        m_logger->timer.start();
    }

    // Format message
    QString formattedMsg;
    QTextStream ts(&formattedMsg, QIODevice::WriteOnly);

    qint64 currentTimeNs = m_logger->timer.nsecsElapsed();
    qint64 totalElapsedMs = currentTimeNs / 1000000;
    qint64 deltaTimeNs = currentTimeNs - m_logger->lastLogTime;
    double deltaTimeMs = deltaTimeNs / 1000000.0;
    m_logger->lastLogTime = currentTimeNs;

    ts << qSetFieldWidth(8) << qSetPadChar(' ') << totalElapsedMs << "ms "
       << "(+" << qSetFieldWidth(7) << qSetPadChar(' ') << QString::asprintf("%.3f", deltaTimeMs)
       << "ms) ";

    switch (type) {
    case QtDebugMsg:
        ts << "Debug: ";
        break;
    case QtInfoMsg:
        ts << "Info: ";
        break;
    case QtWarningMsg:
        ts << "Warning: ";
        break;
    case QtCriticalMsg:
        ts << "Critical: ";
        break;
    case QtFatalMsg:
        ts << "Fatal: ";
        break;
    }
    ts << msg;

    // Send formatted message
    m_logger->sendLog(formattedMsg);

    // Call original handler if it exists
    if (m_logger->originalHandler) {
        m_logger->originalHandler(type, context, msg);
    }
}

void Logger::uninit()
{
    stop();
}
