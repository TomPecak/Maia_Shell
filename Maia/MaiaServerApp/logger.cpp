#include "logger.hpp"

#include <QDebug>
#include <QMutex>
#include <QMutexLocker>
#include <QTextStream>
#include <QTimer>
#include <QtMessageHandler>

Logger *Logger::m_logger = nullptr;

void Logger::setOriginalHandler(QtMessageHandler handler)
{
    originalHandler = handler;
}

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
    connect(&m_socket, &QLocalSocket::connected, this, &Logger::onSocketConnected);
    connect(&m_socket, &QLocalSocket::disconnected, this, &Logger::onSocketDisconnected);
    connect(&m_socket, &QLocalSocket::readyRead, this, &Logger::onSocketReadyRead);
    connect(&m_socket, &QLocalSocket::errorOccurred, this, &Logger::onSocketError);
}

void Logger::run()
{
    //GET LOG CHANNEL FROM ENVIROMENT VARIABLE
    int logChannel = 0;
    if (!qEnvironmentVariableIsEmpty("MAIA_LOG_CHANNEL")) {
        bool ok;
        logChannel = qEnvironmentVariable("MAIA_LOG_CHANNEL").toInt(&ok);
        if (!ok) {
            qDebug() << "Nie udało się skonwertować MAIA_LOG_CHANNEL na liczbę, używam "
                          "domyślnej wartości 0";
            logChannel = 0; // Powrót do domyślnej wartości, jeśli konwersja się nie powiodła
        }
    }

    connectToServer(QString("/tmp/MaiaLogger_channel_%1").arg(logChannel));

    auto originalHandler = qInstallMessageHandler(Logger::messageHandler);
    setOriginalHandler(originalHandler);
}

void Logger::stop()
{
    //qDebug() << __PRETTY_FUNCTION__ << "Stopping logger";
    QMutexLocker locker(&logMutex); // Ensure thread safety

    // Restore the original message handler to prevent further logging through this instance
    if (originalHandler) {
        qInstallMessageHandler(originalHandler);
        originalHandler = nullptr;
    }

    // Disconnect and close the socket
    if (m_socket.isOpen()) {
        m_socket.flush();                // Ensure any pending data is sent
        m_socket.disconnectFromServer(); // Gracefully disconnect
        m_socket.close();                // Close the socket
    }

    // Reset internal state
    reconnect_time = 0;
    m_nextBlockSize = 0;
    m_serverName.clear();
    m_logger = nullptr;

    // Reset timer for consistency
    // timer.invalidate();
    // lastLogTime = 0;
}

void Logger::onSocketConnected()
{
    //qDebug("[OK] Connected to Proxy Window Server");
    reconnect_time = 0;
}

void Logger::onSocketReadyRead()
{
    QDataStream in(&m_socket);

    forever {
        if (m_nextBlockSize == 0) {
            // Jesteśmy na początku nowej ramki, spróbuj odczytać jej rozmiar
            if (m_socket.bytesAvailable() < (int) sizeof(quint32))
                break; // Za mało danych, czekaj na więcej
            in >> m_nextBlockSize;
        }

        if (m_socket.bytesAvailable() < m_nextBlockSize) {
            // Mamy rozmiar, ale cała ramka jeszcze nie przyszła
            break; // Czekaj na resztę danych
        }

        // Mamy całą ramkę, można ją przetworzyć
        //handleStateUpdate(in);

        // Zresetuj rozmiar, aby być gotowym na następną ramkę
        m_nextBlockSize = 0;
    }
}

void Logger::onSocketError(QLocalSocket::LocalSocketError socketError)
{
    // static int errorsCount;
    // errorsCount++;

    //qDebug() << "[ERROR] " << __PRETTY_FUNCTION__ << "Local socket error: " << int(socketError)
    //         << " " << m_socket.errorString() << " socketState: " << int(m_socket.state());

#warning "So, what do we do if the window gets closed?"

    m_socket.close();
    m_socket.abort();

    reconnect_time = qMin(reconnect_time + 1, 5000);
    //qDebug() << "[ERROR] Logger reconnect time = " << reconnect_time << "ms";
    QTimer::singleShot(reconnect_time, this, [this]() { connectToServer(m_serverName); });
}

void Logger::connectToServer(const QString &serverName)
{
    //qDebug() << __PRETTY_FUNCTION__;
    if (m_socket.state() == QLocalSocket::ConnectedState) {
        qDebug() << "[ERROR] " << __PRETTY_FUNCTION__ << " QLocalSocket::ConnectedState";
        return;
    }
    m_serverName = serverName;
    //qDebug() << "Logger: Attempting to connect to" << m_serverName;
    m_socket.connectToServer(m_serverName);
}

void Logger::sendLog(const QString message)
{
    if (m_socket.state() != QLocalSocket::ConnectedState) {
        //qDebug() << "[ERROR] " << __PRETTY_FUNCTION__
        //         << " Controller: Socket not connected. Cannot send command.";
        return;
    }

    QByteArray block;
    QDataStream out(&block, QIODevice::WriteOnly);

    out << (quint32) 0; //reserve space for frame size
    out << static_cast<quint8>(CommandSend::LOG);
    out << message;

    out.device()->seek(0);
    out << (quint32) (block.size() - sizeof(quint32));

    m_socket.write(block);
    m_socket.flush();
}

void Logger::onSocketDisconnected() {}

void Logger::messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    if (!m_logger) {
        return;
    }

    QMutexLocker locker(&m_logger->logMutex);

    if (!m_logger->timer.isValid()) {
        m_logger->timer.start();
    }

    // Formatowanie wiadomości
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

    // Wysłanie wiadomości na socket
    m_logger->sendLog(formattedMsg);

    // Wywołanie oryginalnego handlera, jeśli istnieje
    if (m_logger->originalHandler) {
        m_logger->originalHandler(type, context, msg);
    }
}

void Logger::uninit()
{
    //qDebug() << __PRETTY_FUNCTION__ << "Uninitializing logger";

    stop();

    // Reset timer
    // timer.invalidate();
    // lastLogTime = 0;
}
