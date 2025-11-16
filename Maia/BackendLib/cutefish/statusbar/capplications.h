#pragma once

#include <QObject>
#include <QFileSystemWatcher>

class CAppItem
{
public:
    QString path;
    QString localName;
    QString name;
    QString comment;
    QString icon;
    QString fullExec;
    QString exec;
    QString fileName;
    QString startupWMClass;
};

class CApplications : public QObject
{
    Q_OBJECT

public:
    static CApplications *self();
    explicit CApplications(QObject *parent = nullptr);
    ~CApplications();

    CAppItem *find(const QString &fileName);
    CAppItem *matchItem(quint32 pid, const QString &windowClass);

private:
    void refresh();
    void addApplication(const QString &filePath);
    void removeApplication(CAppItem *item);
    void removeApplications(QList<CAppItem *> items);

    QStringList commandFromPid(quint32 pid);

private:
    QFileSystemWatcher *m_watcher;
    QList<CAppItem *> m_items;
};
