#pragma once

#include <QObject>
#include <QStandardItemModel>
#include "Server.hpp"

class LoggerBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStandardItemModel *logModel READ getLogModel NOTIFY logModelChanged)
    Q_PROPERTY(int channel READ channel WRITE setChannel NOTIFY channelChanged FINAL)

public:
    explicit LoggerBackend(QObject *parent = nullptr);
    ~LoggerBackend();

    QStandardItemModel *getLogModel();

    Q_INVOKABLE void clearCurrentLogModel();

    int channel();
    void setChannel(int channel);

    static constexpr int MAX_ROWS = 10000; // Użycie constexpr
    static constexpr int CHANNELS_COUNT = 10;

signals:
    void channelChanged();
    void logModelChanged();

private:
    void initModel(int channelNumber);
    void initServer(int channelNumber);

    QVector<Server *> servers;
    QVector<QStandardItemModel *> logModels;
    int m_currentChannel = 0;
};
