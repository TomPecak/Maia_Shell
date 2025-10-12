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
    qDBusRegisterMetaType<QVariantList>();

    QDBusConnection bus = QDBusConnection::sessionBus();

    if(!bus.registerService("org.maia.FrontendManager")){
        qDebug("ERROR] Failed to register D-Bus service: %s", qPrintable(bus.lastError().message()));
    }

    //register FronendManager object
    if (!bus.registerObject("/FrontendManager",
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
    emit activeFrontendChanged(m_activeFrontendId);
}

FrontendInfo FrontendManagerService::getCurrentFrontent()
{
    qDebug() << "[INFO] " << __PRETTY_FUNCTION__ << " frontend.name=" << m_frontends[m_activeFrontendId].name;
    return m_frontends[m_activeFrontendId];
}

QVariantList FrontendManagerService::getFrontendList()
{
    QVariantList frontends;
    for(const FrontendInfo &frontend : m_frontends) {
        QVariantMap map;
        map["id"] = frontend.id;
        map["name"] = frontend.name;
        map["description"] = frontend.description;
        map["path"] = frontend.qmlFilePath;
        map["active"] = frontend.id == m_activeFrontendId;
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

    emit activeFrontendChangeRequest(m_frontends[frontendId]);
    emit activeFrontendChangeRequest(frontendId);
}

void FrontendManagerService::loadFrontends()
{
    qDebug() << "[STARTUP INFO] " << __PRETTY_FUNCTION__;
    m_frontends.clear();

    FrontendInfo gnomeFrontend;
    gnomeFrontend.name = "Ubuntu 24.04";
    gnomeFrontend.description = "Ubuntu 24.04 like frontend";

//-----------------------------------------------------------------------------
    QString runType = qgetenv("MAIA_QTCREATOR_RUN");

    if(runType == "1"){ //Maia is running form QtCreator (dev run)
        QString cmake_deploy_prefix = QString::fromStdString(std::string(CMAKE_INSTALL_PREFIX));
        gnomeFrontend.qmlFilePath = cmake_deploy_prefix + QString("/frontends/Gnome/Main.qml");
    }else{  //normal Maia run, form login manager (SDDM, GDM, etc)
        gnomeFrontend.qmlFilePath = QString("/opt/Maia/Maia_") + QString(MAIA_VERSION_STRING) + "/frontends/Gnome/Main.qml";
    }
//-----------------------------------------------------------------------------

    gnomeFrontend.id = QString(
        QCryptographicHash::hash(gnomeFrontend.name.toUtf8(), QCryptographicHash::Sha1).toHex());
    qDebug() << "[STARTUP INFO] Ubuntu 24.04 frontend id = " << gnomeFrontend.id;
    m_frontends.insert(gnomeFrontend.id, gnomeFrontend);


    FrontendInfo lunaFrontend;
    lunaFrontend.name = "XP Luna";
    lunaFrontend.description = "XP Luna like frintend";
 //----------------------------------------------------
    if(runType == "1"){ //Maia is running form QtCreator (dev run)
        QString cmake_deploy_prefix = QString::fromStdString(std::string(CMAKE_INSTALL_PREFIX));
        lunaFrontend.qmlFilePath = cmake_deploy_prefix + QString("/frontends/XPLuna/Main.qml");
    }else{  //normal Maia run, form login manager (SDDM, GDM, etc)
        lunaFrontend.qmlFilePath = QString("/opt/Maia/Maia_") + QString(MAIA_VERSION_STRING) + "/frontends/XPLuna/Main.qml";
    }
//-----------------------------------------------------
    lunaFrontend.id = QString(
        QCryptographicHash::hash(lunaFrontend.name.toUtf8(), QCryptographicHash::Sha1).toHex());
    qDebug() << "[STARTUP INFO] XP Luna frontend id = " << lunaFrontend.id;
    m_frontends.insert(lunaFrontend.id, lunaFrontend);

    FrontendInfo xpFrontend;
    xpFrontend.name = "XP Windows";
    xpFrontend.description = "Windows XP like frontend";
    xpFrontend.qmlFilePath = "";
    xpFrontend.qmlUri = "XPFrontend";
    xpFrontend.qmlTypeName = "Main";
    xpFrontend.id = QString(QCryptographicHash::hash(xpFrontend.name.toUtf8(), QCryptographicHash::Sha1).toHex());
    qDebug() << "[STARTUP INFO] XP Windows frontend id = " << xpFrontend.id;
    m_frontends.insert(xpFrontend.id, xpFrontend);


    QString savedFrontendId = readActiveFronted();
    qDebug() << "[STARTUP INFO] Readed saved frontend id=" << savedFrontendId;

    // Set the active frontend: saved if it exists and is valid, otherwise default
    if (!savedFrontendId.isEmpty() && m_frontends.contains(savedFrontendId)) {
        m_activeFrontendId = savedFrontendId;
    } else {
        m_activeFrontendId = m_frontends.isEmpty() ? "" : gnomeFrontend.id; // Default frontend
    }

    // Emit signal if the active frontend is set
    if (!m_activeFrontendId.isEmpty()) {
        emit activeFrontendChanged(m_activeFrontendId);
    }
}

void FrontendManagerService::addFrontend(const FrontendInfo &frontend)
{
    m_frontends.insert(frontend.id, frontend);
    emit frontendAdded(frontend.id, frontend.name, frontend.description, frontend.qmlFilePath);
}

void FrontendManagerService::removeFrontend(const QString &frontendId)
{
    if (m_frontends.remove(frontendId)) {
        emit frontendRemoved(frontendId);
        if (m_activeFrontendId == frontendId && !m_frontends.isEmpty()) {
            // Use iterator to get an arbitrary key
            setActiveFrontend(m_frontends.firstKey());
        }
    }
}

QString FrontendManagerService::readActiveFronted()
{
#warning "this code is not asynchronous"

    KSharedConfig::Ptr config = KSharedConfig::openConfig(QString("./Maia/maiarc_")
                                                          + MAIA_VERSION_STRING);
    KConfigGroup group = config->group("FrontendManagerService");
    return group.readEntry("activeFrontendId", QString());
}

void FrontendManagerService::saveActiveFronted(const QString &frontedId)
{
#warning "This method is not asynchronous"

    // Save activeFrontendId to KSharedConfig
    KSharedConfig::Ptr config = KSharedConfig::openConfig(
        QString("./Maia/maiarc_")
        + MAIA_VERSION_STRING); // Configuration file name, e.g., ~/.config/Maia/maiarc_0.1.0
    KConfigGroup group = config->group("FrontendManagerService");
    group.writeEntry("activeFrontendId", frontedId);
    config->sync(); // Ensure saving to the file
}
