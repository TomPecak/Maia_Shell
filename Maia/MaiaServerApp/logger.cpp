#include "logger.hpp"

#include <QDebug>
#include <QMutexLocker>
#include <QTextStream>
#include <QTimer>
#include <QProcessEnvironment>
#include <QCoreApplication>

Logger *Logger::m_logger = nullptr;

Logger::Logger(QObject *parent)
    : QObject(parent)
{
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

void Logger::setOriginalHandler(QtMessageHandler handler)
{
    originalHandler = handler;
}

QString Logger::constructServerUrl()
{
    QString host = qEnvironmentVariable("MAIA_LOG_HOST", QStringLiteral("localhost"));

    int logPort = 50000;
    if (!qEnvironmentVariableIsEmpty("MAIA_LOG_PORT")) {
        bool ok;
        logPort = qEnvironmentVariable("MAIA_LOG_PORT").toInt(&ok);
        if (!ok) {
            qWarning() << "[LOGGER CONFIG] MAIA_LOG_PORT is not a valid number. Fallback to 50000.";
            logPort = 50000;
        }
    }

    // Ponieważ ta funkcja wywoływana jest po instalacji handlera, ten log trafi do pliku i do sieci!
    qInfo() << "[LOGGER CONFIG] WebSocket URL configured as -> ws://" << host << ":" << logPort;
    return QStringLiteral("ws://%1:%2").arg(host).arg(logPort);
}

void Logger::setupFileLogging()
{
    QString logFilePath = qEnvironmentVariable("MAIA_LOG_FILE");
    if (logFilePath.isEmpty()) {
        qDebug() << "[LOGGER CONFIG] MAIA_LOG_FILE is not set. File logging is DISABLED.";
        return;
    }

    m_logFile = std::make_unique<QFile>(logFilePath);
    if (m_logFile->open(QIODevice::WriteOnly | QIODevice::Text)) {

        QTextStream stream(m_logFile.get());

        // 1. Zrzut środowiska bezpośrednio do otwartego pliku
        stream << "========== ENVIRONMENT VARIABLES ==========\n";
        QStringList envVars = QProcessEnvironment::systemEnvironment().toStringList();
        for (const QString &env : envVars) {
            stream << env << "\n";
        }
        stream << "===========================================\n";

        // 2. Info o udanym otwarciu zapisane prosto do pliku
        stream << "[LOGGER INFO] Successfully opened and initialized log file: " << logFilePath << "\n\n";
        m_logFile->flush();

        qInfo() << "[LOGGER CONFIG] File logging ENABLED. Output file:" << logFilePath;
    } else {
        qWarning() << "[LOGGER ERROR] Failed to open log file:" << logFilePath
                   << "Error:" << m_logFile->errorString();
        m_logFile.reset(); // Zabezpieczenie przed używaniem uszkodzonego wskaźnika
    }
}

void Logger::run()
{
    // Informacja na systemową konsolę (jeszcze przez domyślny systemowy handler)
    qInfo() << "===========================================";
    qInfo() << "[LOGGER INIT] Initializing Maia Logger...";

    // 1. Otwieramy plik, zrzucamy środowisko.
    setupFileLogging();

    // 2. Od teraz PRZEJMUJEMY LOGI (wszystko poniżej pójdzie już też do pliku i przez sieć)
    auto oldHandler = qInstallMessageHandler(Logger::messageHandler);
    setOriginalHandler(oldHandler);

    qInfo() << "[LOGGER INIT] Custom Qt Message Handler installed. Capturing logs...";

    // 3. Budujemy adres i łączymy się. Wynikowe logi konfiguracyjne z 'constructServerUrl'
    //    zostaną przechwycone i zapiszą się w nowo utworzonym pliku.
    QString url = constructServerUrl();
    connectToServer(url);
}

void Logger::stop()
{
    if (originalHandler) {
        qInstallMessageHandler(originalHandler);
        originalHandler = nullptr;
    }

    QMutexLocker locker(&logMutex);

    if (m_socket.isValid()) {
        m_socket.close();
    }

    if (m_logFile && m_logFile->isOpen()) {
        m_logFile->close();
    }

    reconnect_time = 0;
    m_serverUrl.clear();
    m_logger = nullptr;
}

void Logger::uninit()
{
    stop();
}

void Logger::onSocketConnected()
{
    qInfo() << "[LOGGER NETWORK] Connected successfully to Logger server at" << m_serverUrl;
    reconnect_time = 0;
    sendBufferedLogs();
}

void Logger::onTextMessageReceived(const QString &message)
{
    Q_UNUSED(message);
}

void Logger::onSocketError(QAbstractSocket::SocketError socketError)
{
    Q_UNUSED(socketError);
    // Logujemy awarię (trafi do pliku logów, bo mamy przejęty handler)
    qWarning() << "[LOGGER NETWORK] WebSocket connection error:" << m_socket.errorString();

    m_socket.close();

    reconnect_time = qMin(reconnect_time + 1000, 5000);
    QTimer::singleShot(reconnect_time, this, [this]() { connectToServer(m_serverUrl); });
}

void Logger::onSocketDisconnected()
{
    qInfo() << "[LOGGER NETWORK] Disconnected from Logger server. Retrying...";
    reconnect_time = qMin(reconnect_time + 1000, 5000);
    QTimer::singleShot(reconnect_time, this, [this]() { connectToServer(m_serverUrl); });
}

void Logger::connectToServer(const QString &serverUrl)
{
    if (m_socket.isValid() && m_socket.state() != QAbstractSocket::UnconnectedState) {
        return;
    }
    m_serverUrl = serverUrl;
    m_socket.open(QUrl(serverUrl));
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

void Logger::processQueuedLogs()
{
    sendBufferedLogs();
}

void Logger::messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    if (!m_logger) return;

    QString formattedMsg;
    {
        QMutexLocker locker(&m_logger->logMutex);

        if (!m_logger->timer.isValid()) {
            m_logger->timer.start();
        }

        qint64 currentTimeNs = m_logger->timer.nsecsElapsed();
        qint64 totalElapsedMs = currentTimeNs / 1000000;
        qint64 deltaTimeNs = currentTimeNs - m_logger->lastLogTime;
        double deltaTimeMs = deltaTimeNs / 1000000.0;
        m_logger->lastLogTime = currentTimeNs;

        QTextStream ts(&formattedMsg, QIODevice::WriteOnly);
        ts << qSetFieldWidth(8) << qSetPadChar(u' ') << totalElapsedMs << "ms "
           << "(+" << qSetFieldWidth(7) << qSetPadChar(u' ') << QString::asprintf("%.3f", deltaTimeMs)
           << "ms) ";

        switch (type) {
        case QtDebugMsg:    ts << "Debug: "; break;
        case QtInfoMsg:     ts << "Info: "; break;
        case QtWarningMsg:  ts << "Warning: "; break;
        case QtCriticalMsg: ts << "Critical: "; break;
        case QtFatalMsg:    ts << "Fatal: "; break;
        }
        ts << msg;

        // Jeśli plik otwarty, zapisz z mocnym wymuszeniem zrzutu na dysk (flush)
        // Jeśli plik otwarty, zapisz z mocnym wymuszeniem zrzutu na dysk (flush)
        if (m_logger->m_logFile && m_logger->m_logFile->isOpen()) {
            QByteArray logBytes = formattedMsg.toUtf8();
            logBytes.append('\n'); // Bezpieczne operowanie na bajtach, omija QStringBuilder
            m_logger->m_logFile->write(logBytes);
            m_logger->m_logFile->flush();
        }

        if (m_logger->m_logBuffer.size() >= m_logger->MAX_BUFFER_SIZE) {
            m_logger->m_logBuffer.dequeue();
        }
        m_logger->m_logBuffer.enqueue(formattedMsg);
    }

    QMetaObject::invokeMethod(m_logger, "processQueuedLogs", Qt::QueuedConnection);

    if (m_logger->originalHandler) {
        m_logger->originalHandler(type, context, msg);
    }
}
