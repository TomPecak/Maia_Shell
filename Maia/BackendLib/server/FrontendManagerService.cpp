#include "FrontendManagerService.hpp"
#include "frontendmanager_adaptor.h"
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusError>
#include <QDir>
#include <QFileInfo>
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
    qDBusRegisterMetaType<QList<QVariantMap>>();
    new FrontendManagerAdaptor(this);

    QDBusConnection bus = QDBusConnection::sessionBus();

    if(!bus.registerService(QStringLiteral("org.maia.FrontendManager"))){
        qDebug("ERROR] Failed to register D-Bus service: %s", qPrintable(bus.lastError().message()));
    }

    //register FronendManager object
    if (!bus.registerObject(QStringLiteral("/FrontendManager"), this, QDBusConnection::ExportAdaptors)) {
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

QList<QVariantMap> FrontendManagerService::getFrontendList()
{
    QList<QVariantMap> frontends;
    for (const FrontendInfo &frontend : std::as_const(m_frontends))
        frontends.append(frontendMap(frontend));
    return frontends;
}

// One frontend as described in the contract (dbus/org.maia.FrontendManager.xml)
QVariantMap FrontendManagerService::frontendMap(const FrontendInfo &frontend) const
{
    return {
        {QStringLiteral("id"), frontend.id},
        {QStringLiteral("name"), frontend.name},
        {QStringLiteral("description"), frontend.description},
        {QStringLiteral("path"), frontend.qmlFilePath},
        {QStringLiteral("rootPath"), frontend.rootPath},
        {QStringLiteral("active"), frontend.id == m_activeFrontendId},
    };
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
    // Skanowanie katalogu z frontendami
    // ========================================================================
    // Każdy podkatalog zawierający shell/Main.qml (punkt wejścia shella) jest traktowany jako frontend.
    // Nazwa i opis to nazwa katalogu, id to hash SHA1 nazwy katalogu.
    QDir baseDir(basePath);
    if (!baseDir.exists()) {
        qDebug() << "[ERROR] Frontends directory does not exist:" << basePath;
    }

    const QStringList dirNames = baseDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &dirName : dirNames) {
        const QString mainQmlPath = baseDir.filePath(dirName + QStringLiteral("/shell/Main.qml"));

        if (!QFileInfo::exists(mainQmlPath)) {
            qDebug() << "[ INFO ] Skipping directory" << dirName << "- no shell/Main.qml file";
            continue;
        }

        FrontendInfo frontend;
        frontend.name = dirName;
        frontend.description = dirName;
        frontend.qmlFilePath = mainQmlPath;
        frontend.rootPath = QFileInfo(baseDir.filePath(dirName)).absoluteFilePath();
        frontend.id = QString::fromUtf8(
            QCryptographicHash::hash(dirName.toUtf8(), QCryptographicHash::Sha1).toHex());

        qDebug() << "[STARTUP INFO] Found frontend" << frontend.name << "id =" << frontend.id
                 << "qml =" << frontend.qmlFilePath;
        m_frontends.insert(frontend.id, frontend);
    }

    if (m_frontends.isEmpty()) {
        qDebug() << "[ERROR] No frontends found in:" << basePath;
    }

    // ========================================================================
    // Aktywacja zapisanego frontendu
    // ========================================================================
    // TYMCZASOWO WYŁĄCZONE: Maia zawsze startuje z domyślnym frontendem "Ubuntu 24.04",
    // zapisany wybór z konfiguracji jest ignorowany (nadal jest zapisywany przy przełączaniu).
    // QString savedFrontendId = readActiveFronted();
    // qDebug() << "[STARTUP INFO] Readed saved frontend id=" << savedFrontendId;
    //
    // // Ustaw aktywny frontend: zapisany jeśli istnieje, w przeciwnym razie domyślny
    // if (!savedFrontendId.isEmpty() && m_frontends.contains(savedFrontendId)) {
    //     m_activeFrontendId = savedFrontendId;
    // } else {

    // Domyślny: "Ubuntu 24.04" jeśli istnieje, w przeciwnym razie pierwszy znaleziony
    const QString defaultFrontendId = QString::fromUtf8(
        QCryptographicHash::hash(QByteArrayLiteral("Ubuntu 24.04"), QCryptographicHash::Sha1).toHex());
    if (m_frontends.contains(defaultFrontendId)) {
        m_activeFrontendId = defaultFrontendId;
    } else {
        qDebug() << "[ERROR] Default frontend \"Ubuntu 24.04\" not found, using the first available one";
        m_activeFrontendId = m_frontends.isEmpty() ? QStringLiteral("") : m_frontends.firstKey();
    }
    qDebug() << "[STARTUP INFO] Starting with default frontend id=" << m_activeFrontendId;

    // }

    // Wyślij sygnał o zmianie
    if (!m_activeFrontendId.isEmpty()) {
        Q_EMIT activeFrontendChanged(m_activeFrontendId);
    }
}

void FrontendManagerService::addFrontend(const FrontendInfo &frontend)
{
    m_frontends.insert(frontend.id, frontend);
    Q_EMIT frontendAdded(frontendMap(frontend));
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
