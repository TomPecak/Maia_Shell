#ifndef PROCESSPROVIDERLAUNCHER_H
#define PROCESSPROVIDERLAUNCHER_H

#include <QObject>

class ProcessProviderLauncher : public QObject
{
    Q_OBJECT

public:
    explicit ProcessProviderLauncher(QObject *parent = nullptr);

    Q_INVOKABLE static bool startDetached(const QString &exec, QStringList args = QStringList());
};

#endif // PROCESSPROVIDERLAUNCHER_H
