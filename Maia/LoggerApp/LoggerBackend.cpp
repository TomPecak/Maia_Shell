#include "LoggerBackend.hpp"

LoggerBackend::LoggerBackend(QObject *parent)
    : QObject(parent)
{
    for (int i = 0; i < CHANNELS_COUNT; i++) {
        servers.append(new Server(this));
    }

    for (int i = 0; i < CHANNELS_COUNT; i++) {
        logModels.append(new QStandardItemModel(this));
    }

    //MODEL CONFIG
    for (int channel = 0; channel < CHANNELS_COUNT; channel++) {
        initModel(channel);
    }

    //SERVER CONFIG
    for (int channel = 0; channel < CHANNELS_COUNT; channel++) {
        initServer(channel);
    }
}

LoggerBackend::~LoggerBackend() {}

void LoggerBackend::initModel(int channelNumber)
{
    logModels[channelNumber]->setRowCount(1);
    logModels[channelNumber]->setColumnCount(1);

    QHash<int, QByteArray> roleNames;
    roleNames[Qt::DisplayRole] = "process_id";
    roleNames[Qt::UserRole + 1] = "message";
    logModels[channelNumber]->setItemRoleNames(roleNames);

    for (int row = 0; row < logModels.at(channelNumber)->rowCount(); ++row) {
        QStandardItem *item = new QStandardItem();
        item->setData(QString("[OK] Test Model"), Qt::DisplayRole); // Pierwsze pole
        //item->setData(QString("Dodatkowy tekst %1").arg(row + 1), Qt::UserRole + 1); // Drugie pole
        logModels[channelNumber]->setItem(row, 0, item);
    }
}

void LoggerBackend::initServer(int channelNumber)
{
    connect(servers[channelNumber],
            &Server::messageReceived,
            this,
            [=](int clientId, QLocalSocket *socket, QString message) {
                QStandardItem *item = new QStandardItem();
                item->setData(QString::number(clientId), Qt::DisplayRole);
                item->setData(message, Qt::UserRole + 1);
                if (logModels[channelNumber]->rowCount() >= MAX_ROWS) {
                    logModels[channelNumber]->removeRow(0);
                }
                logModels[channelNumber]->appendRow(item);
            });
    servers[channelNumber]->startServer(QString("/tmp/MaiaLogger_channel_%1").arg(channelNumber));
}

QStandardItemModel *LoggerBackend::getLogModel()
{
    return logModels[m_currentChannel];
}

void LoggerBackend::clearCurrentLogModel()
{
    logModels[m_currentChannel]->removeRows(0, logModels[m_currentChannel]->rowCount());
}

int LoggerBackend::channel()
{
    return m_currentChannel;
}

void LoggerBackend::setChannel(int channel)
{
    if (m_currentChannel != channel) {
        m_currentChannel = channel;
        emit channelChanged();
        emit logModelChanged();
    }
}
