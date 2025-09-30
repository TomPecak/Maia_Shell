#pragma once

#include <QQuickImageProvider>
#include <QPixmap>
#include <QAbstractListModel>
#include <QImage>
#include <QUrl>
#include <QFile>

class TaskbarIconsProvider : public QQuickImageProvider
{
public:
    explicit TaskbarIconsProvider();
    ~TaskbarIconsProvider();

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
    QString getProcessNameByPid(qint64 pid);
};
