#include "LoggerBackend.hpp"

#include <QProcess>
#include <QNetworkInterface>

LoggerBackend::LoggerBackend(QObject *parent)
    : QObject(parent)
{
    for (int port = 0 + 50000; port < PORT_CHANNELS_COUNT + 50000; port++) {
        servers[port] = new Server(this);
    }

    for (int port = 0 + 50000; port < PORT_CHANNELS_COUNT + 50000; port++) {
        logModels[port] = new QStandardItemModel(this);
    }

    //MODEL CONFIG
    for (int port = 0 + 50000; port < PORT_CHANNELS_COUNT + 50000; port++) {
        initModel(port);
    }

    //SERVER CONFIG
    for (int port = 0 + 50000; port < PORT_CHANNELS_COUNT + 50000; port++) {
        initServer(port);
    }
}

LoggerBackend::~LoggerBackend() {}

void LoggerBackend::initModel(int port)
{
    logModels[port]->setRowCount(1);
    logModels[port]->setColumnCount(1);

    QHash<int, QByteArray> roleNames;
    roleNames[Qt::DisplayRole] = "process_id";
    roleNames[Qt::UserRole + 1] = "message";
    logModels[port]->setItemRoleNames(roleNames);

    for (int row = 0; row < logModels[port]->rowCount(); ++row) {
        QStandardItem *item = new QStandardItem();
        item->setData(QString("[OK] Test Model"), Qt::DisplayRole); // Pierwsze pole
        //item->setData(QString("Dodatkowy tekst %1").arg(row + 1), Qt::UserRole + 1); // Drugie pole
        logModels[port]->setItem(row, 0, item);
    }
}

void LoggerBackend::initServer(int port)
{
    connect(servers[port],
            &Server::messageReceived,
            this,
            [=](int clientId, QWebSocket *socket, QString message) {
                QStandardItem *item = new QStandardItem();
                item->setData(QString::number(clientId), Qt::DisplayRole);
                item->setData(message, Qt::UserRole + 1);
                if (logModels[port]->rowCount() >= MAX_ROWS) {
                    logModels[port]->removeRow(0);
                }
                logModels[port]->appendRow(item);
            });
    servers[port]->startServer(port);
}

QStandardItemModel *LoggerBackend::getLogModel()
{
    return logModels[m_currentPort];
}

void LoggerBackend::clearCurrentLogModel()
{
    logModels[m_currentPort]->removeRows(0, logModels[m_currentPort]->rowCount());
}

int LoggerBackend::port()
{
    return m_currentPort;
}

void LoggerBackend::setPort(int port)
{
    if (m_currentPort != port) {
        m_currentPort = port;
        emit portChanged();
        emit logModelChanged();
        emit serverAddressesChanged();
    }
}

QStringList LoggerBackend::serverAddresses()
{
    QStringList addresses;
    for (const QHostAddress &address : QNetworkInterface::allAddresses()) {
        if (address.protocol() == QAbstractSocket::IPv4Protocol) {
            addresses << QString("ws://%1:%2").arg(address.toString()).arg(m_currentPort);
        }
    }
    return addresses;
}

