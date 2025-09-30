#include "ProxyWindowController.hpp"

#include <QDebug>
#include <QTimer>

ProxyWindowController::ProxyWindowController(QObject *parent)
    : QObject(parent)
{
    connect(&m_socket, &QLocalSocket::connected, this, &ProxyWindowController::onSocketConnected);
    connect(&m_socket,
            &QLocalSocket::disconnected,
            this,
            &ProxyWindowController::onSocketDisconnected);
    connect(&m_socket, &QLocalSocket::readyRead, this, &ProxyWindowController::onSocketReadyRead);
    connect(&m_socket, &QLocalSocket::errorOccurred, this, &ProxyWindowController::onSocketError);
}

ProxyWindowController::~ProxyWindowController()
{
    if (m_socket.isOpen()) {
        m_socket.flush();
        m_socket.close();
        m_socket.disconnect();
    }
}

void ProxyWindowController::setVisible(bool visible)
{
    sendSetVisible(visible);
}

void ProxyWindowController::quitRemoteProcess()
{
    if (m_socket.state() != QLocalSocket::ConnectedState) {
        qDebug() << "[ERROR] " << __PRETTY_FUNCTION__
                   << " Controller: Socket not connected. Cannot send command.";
        return;
    }

    QByteArray block;
    QDataStream out(&block, QIODevice::WriteOnly);

    out << (quint32) 0; //reserve space for frame size
    out << static_cast<quint8>(CommandSend::QUIT_PROCESS);

    out.device()->seek(0);
    out << (quint32) (block.size() - sizeof(quint32));

    m_socket.write(block);
    m_socket.flush();
}

void ProxyWindowController::sendSetVisible(bool visible)
{
    qDebug() << __PRETTY_FUNCTION__;
    if (m_socket.state() != QLocalSocket::ConnectedState) {
        qDebug() << "[ERROR] " << __PRETTY_FUNCTION__
                   << " Controller: Socket not connected. Cannot send command.";
        return;
    }

    QByteArray block;
    QDataStream out(&block, QIODevice::WriteOnly);

    out << (quint32) 0; //reserve space for frame size
    out << static_cast<quint8>(CommandSend::SET_VISIBLE);
    out << visible;

    out.device()->seek(0);
    out << (quint32) (block.size() - sizeof(quint32));

    m_socket.write(block);
    m_socket.flush();
}

void ProxyWindowController::connectToServer(const QString &serverName)
{
    if (m_socket.state() == QLocalSocket::ConnectedState) {
        qDebug() << "[ERROR] " << __PRETTY_FUNCTION__ << " QLocalSocket::ConnectedState";
        return;
    }
    m_serverName = serverName;
    m_socket.connectToServer(m_serverName);
}

void ProxyWindowController::onSocketConnected()
{
    reconnect_time = 0;
    emit proxyWindowConnected();
}

void ProxyWindowController::onSocketDisconnected() {}

void ProxyWindowController::onSocketReadyRead()
{
    QDataStream in(&m_socket);

    forever {
        if (m_nextBlockSize == 0) {
            // We are at the beginning of a new frame, try to read its size
            if (m_socket.bytesAvailable() < (int) sizeof(quint32))
                break; // Not enough data, wait for more
            in >> m_nextBlockSize;
        }

        if (m_socket.bytesAvailable() < m_nextBlockSize) {
            // We have the size, but the entire frame hasn't arrived yet
            break; // Wait for the rest of the data
        }

        // We have the entire frame, it can be processed
        handleStateUpdate(in);

        // Reset the size to be ready for the next frame
        m_nextBlockSize = 0;
    }
}

void ProxyWindowController::handleStateUpdate(QDataStream &stream)
{
    quint8 updateTypeRaw;
    stream >> updateTypeRaw;
    auto updateType = static_cast<CommandReceived>(updateTypeRaw);

    if (updateType == CommandReceived::SET_VISIBLE) {
        bool serverVisible;
        stream >> serverVisible;
        emit visibleReceived(serverVisible);
    } else {
        qDebug() << "[ERROR] ProxyWindowController: Received unknown state update type:" << updateTypeRaw;
    }
}

void ProxyWindowController::onSocketError(QLocalSocket::LocalSocketError socketError)
{
    // static int errorsCount;
    // errorsCount++;

    //qDebug() << "[ERROR] " << __PRETTY_FUNCTION__ << "Local socket error: " << int(socketError)
    //         << " " << m_socket.errorString() << " socketState: " << int(m_socket.state());

#warning "So, what do we do if the window gets closed?"

    m_socket.close();
    m_socket.abort();

    //qDebug() << "[INFO] Proxy Window reconnect time = " << reconnect_time << "ms";
    QTimer::singleShot(reconnect_time++, this, [this]() { connectToServer(m_serverName); });
}
