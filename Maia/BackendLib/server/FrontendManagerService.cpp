#include "FrontendManagerService.hpp"
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusError>
#include <QDir>
#include <QUuid>
#include <qdbusmetatype.h>

#include <KSharedConfig>
#include <KConfigGroup>

#include <cmake_config.h>
#include "../maia_version.h"


FrontendManagerService::FrontendManagerService(QObject *parent) :
    QObject(parent)
{
            qDebug() << "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH UJ 222222222 !!!";
    qDBusRegisterMetaType<QVariantList>();

    QDBusConnection bus = QDBusConnection::sessionBus();

    if(!bus.registerService(QStringLiteral("org.maia.FrontendManager"))){
        qDebug("ERROR] Failed to register D-Bus service: %s", qPrintable(bus.lastError().message()));
    }

    //register FronendManager object
    if (!bus.registerObject(QStringLiteral("/FrontendManager"),
                            this,
                            QDBusConnection::ExportAllSlots
                                | QDBusConnection::ExportScriptableSignals
                                | QDBusConnection::ExportAllProperties)) {
        qDebug("[ERROR] Failed to register D-Bus object: %s", qPrintable(bus.lastError().message()));
    }

    loadFrontends();
}

FrontendManagerService::~FrontendManagerService()
{

}

void FrontendManagerService::activeFrontendChangeConfirmation(const QString &frontendId)
{
    if (m_activeFrontendId == frontendId)
        return;

    m_activeFrontendId = frontendId;

    saveActiveFronted(m_activeFrontendId);
    Q_EMIT activeFrontendChanged(m_activeFrontendId);
}

FrontendInfo FrontendManagerService::getCurrentFrontent()
{
    qDebug() << "[ INFO ] " << __PRETTY_FUNCTION__ << " frontend.name=" << m_frontends[m_activeFrontendId].name;
    return m_frontends[m_activeFrontendId];
}

QVariantList FrontendManagerService::getFrontendList()
{
    QVariantList frontends;
    for(const FrontendInfo &frontend : m_frontends) {
        QVariantMap map;
        map[QStringLiteral("id")] = frontend.id;
        map[QStringLiteral("name")] = frontend.name;
        map[QStringLiteral("description")] = frontend.description;
        map[QStringLiteral("path")] = frontend.qmlFilePath;
        map[QStringLiteral("active")] = frontend.id == m_activeFrontendId;
        frontends.append(map);
    }
    return frontends;
}

QString FrontendManagerService::activeFrontend() const
{
    return m_activeFrontendId;
}

//d-bus interface
void FrontendManagerService::setActiveFrontend(const QString &frontendId)
{
    if (frontendId.isEmpty()) {
        return;
    }

    if (m_activeFrontendId == frontendId) {
        return;
    }


    if (!m_frontends.contains(frontendId)) {
        qDebug() << "[ERROR] Frontend with ID" << frontendId << "not found.";
        return;
    }

    Q_EMIT activeFrontendChangeRequest(m_frontends[frontendId]);
    Q_EMIT activeFrontendChangeRequest(frontendId);
}

void FrontendManagerService::loadFrontends()
{
    qDebug() << "[ INFO ] " << __PRETTY_FUNCTION__;
    m_frontends.clear();

    // 1. Ustalenie ścieżki bazowej dla frontendów
    QString basePath;
    QString envFrontendPath = QString::fromUtf8(qgetenv("MAIA_FRONTENDS_PATH"));

    if (!envFrontendPath.isEmpty()) {
        // Uruchomienie deweloperskie ze wskazaną ścieżką
        basePath = envFrontendPath;
        qDebug() << "[ INFO ] MAIA_FRONTENDS_PATH is set. Using custom frontend path:" << basePath;
    } else {
        // Standardowe uruchomienie (np. przez menedżer logowania)
        basePath = QStringLiteral("/opt/Maia/Maia_") + QStringLiteral(MAIA_VERSION_STRING) + QStringLiteral("/frontends");
        qDebug() << "[ INFO ] Using default frontend path:" << basePath;
    }

    // ========================================================================
    // Ubuntu 24.04
    // ========================================================================
    FrontendInfo gnomeFrontend;
    gnomeFrontend.name = QStringLiteral("Ubuntu 24.04");
    gnomeFrontend.description = QStringLiteral("Ubuntu 24.04 like frontend");
    gnomeFrontend.qmlFilePath = basePath + QStringLiteral("/Gnome/Main.qml");
    gnomeFrontend.id = QString::fromUtf8(
        QCryptographicHash::hash(gnomeFrontend.name.toUtf8(), QCryptographicHash::Sha1).toHex());

    qDebug() << "[STARTUP INFO] Ubuntu 24.04 frontend id =" << gnomeFrontend.id;
    m_frontends.insert(gnomeFrontend.id, gnomeFrontend);

    // ========================================================================
    // XP Luna
    // ========================================================================
    FrontendInfo lunaFrontend;
    lunaFrontend.name = QStringLiteral("XP Luna");
    lunaFrontend.description = QStringLiteral("XP Luna like frontend");
    lunaFrontend.qmlFilePath = basePath + QStringLiteral("/XPLuna/Main.qml");
    lunaFrontend.id = QString::fromUtf8(
        QCryptographicHash::hash(lunaFrontend.name.toUtf8(), QCryptographicHash::Sha1).toHex());

    qDebug() << "[STARTUP INFO] XP Luna frontend id =" << lunaFrontend.id;
    m_frontends.insert(lunaFrontend.id, lunaFrontend);

    // ========================================================================
    // CutefishOS
    // ========================================================================
    FrontendInfo cutefishFrontend;
    cutefishFrontend.name = QStringLiteral("CutefishOS");
    cutefishFrontend.description = QStringLiteral("CutefishOS like frontend");
    cutefishFrontend.qmlFilePath = basePath + QStringLiteral("/Cutefish/Main.qml");

    qDebug() << "KKKKKKKKKKKKKKKUrwa cutefish qml path: " << cutefishFrontend.qmlFilePath;

    cutefishFrontend.id = QString::fromUtf8(
        QCryptographicHash::hash(cutefishFrontend.name.toUtf8(), QCryptographicHash::Sha1).toHex());

    qDebug() << "[STARTUP INFO] CutefishOS frontend id =" << cutefishFrontend.id;
    m_frontends.insert(cutefishFrontend.id, cutefishFrontend);

    // ========================================================================
    // Aktywacja zapisanego frontendu
    // ========================================================================
    QString savedFrontendId = readActiveFronted();
    qDebug() << "[STARTUP INFO] Readed saved frontend id=" << savedFrontendId;

    // Ustaw aktywny frontend: zapisany jeśli istnieje, w przeciwnym razie domyślny
    if (!savedFrontendId.isEmpty() && m_frontends.contains(savedFrontendId)) {
        m_activeFrontendId = savedFrontendId;
    } else {
        m_activeFrontendId = m_frontends.isEmpty() ? QStringLiteral("") : gnomeFrontend.id; // Domyślny
    }

    // Wyślij sygnał o zmianie
    if (!m_activeFrontendId.isEmpty()) {
        Q_EMIT activeFrontendChanged(m_activeFrontendId);
    }
}

void FrontendManagerService::addFrontend(const FrontendInfo &frontend)
{
    m_frontends.insert(frontend.id, frontend);
    Q_EMIT frontendAdded(frontend.id, frontend.name, frontend.description, frontend.qmlFilePath);
}

void FrontendManagerService::removeFrontend(const QString &frontendId)
{
    if (m_frontends.remove(frontendId)) {
        Q_EMIT frontendRemoved(frontendId);
        if (m_activeFrontendId == frontendId && !m_frontends.isEmpty()) {
            // Use iterator to get an arbitrary key
            setActiveFrontend(m_frontends.firstKey());
        }
    }
}

QString FrontendManagerService::readActiveFronted()
{
#warning "this code is not asynchronous"

    KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("./Maia/maiarc_")
                                                          + QStringLiteral(MAIA_VERSION_STRING));
    KConfigGroup group = config->group(QStringLiteral("FrontendManagerService"));
    return group.readEntry("activeFrontendId", QString());
}

void FrontendManagerService::saveActiveFronted(const QString &frontedId)
{
#warning "This method is not asynchronous"

    // Save activeFrontendId to KSharedConfig
    KSharedConfig::Ptr config = KSharedConfig::openConfig(
        QStringLiteral("./Maia/maiarc_")
        + QStringLiteral(MAIA_VERSION_STRING)); // Configuration file name, e.g., ~/.config/Maia/maiarc_0.1.0
    KConfigGroup group = config->group(QStringLiteral("FrontendManagerService"));
    group.writeEntry("activeFrontendId", frontedId);
    config->sync(); // Ensure saving to the file
}
