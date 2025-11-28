#pragma once

#include <QObject>
#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

class LocaleSettingsService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool twentyFourTime READ twentyFourTime WRITE setTwentyFourTime NOTIFY twentyFourTimeChanged)
    Q_CLASSINFO("D-Bus Interface", "com.maia.LocaleSettings")

public:
    explicit LocaleSettingsService(QObject *parent = nullptr);
    ~LocaleSettingsService();

    bool twentyFourTime() const;

public slots:
    void setTwentyFourTime(bool newTwentyFourTime);

signals:
    void twentyFourTimeChanged(bool newTwentyFourTime);

private:
    // Metody pomocnicze do obsługi KConfig
    void loadSettings();
    void saveSettings();

    bool m_twentyFourTime;
    bool m_isRegistered;

    const QString ServiceName = QStringLiteral("com.maia.LocaleSettings");
    const QString ObjectPath  = QStringLiteral("/LocaleSettings");
    const QString Interface   = QStringLiteral("com.maia.LocaleSettings");
};
