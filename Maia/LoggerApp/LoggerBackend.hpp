#pragma once

#include <QObject>
#include <QStandardItemModel>
#include <QMap>

#include "Server.hpp"

class LoggerBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStandardItemModel *logModel READ getLogModel NOTIFY logModelChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged FINAL)
    Q_PROPERTY(QStringList serverAddresses READ serverAddresses NOTIFY serverAddressesChanged FINAL)

public:
    explicit LoggerBackend(QObject *parent = nullptr);
    ~LoggerBackend();

    QStandardItemModel *getLogModel();

    Q_INVOKABLE void clearCurrentLogModel();

    int port();
    void setPort(int port);
    QStringList serverAddresses();

    static constexpr int MAX_ROWS = 10000;
    static constexpr int PORT_CHANNELS_COUNT = 10;

signals:
    void portChanged();
    void logModelChanged();
    void serverAddressesChanged();

private:
    void initModel(int portNumber);
    void initServer(int portNumber);

    QMap<int, Server *> servers; //key - port number, value - Server *
    QMap<int, QStandardItemModel *> logModels; //key - port number, value - QStandardItemModel *
    int m_currentPort = 50000;
};
