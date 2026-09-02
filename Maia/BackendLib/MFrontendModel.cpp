#include "MFrontendModel.hpp"

#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QVariant>
#include <QVariantList>
#include <qdbusmetatype.h>

MFrontendModel::MFrontendModel(QObject *parent)
    : QAbstractListModel(parent)
{
    qDBusRegisterMetaType<QVariantMap>();
    qDBusRegisterMetaType<QVariantList>();

    m_dbusInterface = new QDBusInterface(
        "org.maia.FrontendManager",
        "/FrontendManager",
        "org.maia.FrontendManager",
        QDBusConnection::sessionBus(),
        this);

    connect(
        m_dbusInterface,
        SIGNAL(frontendAdded(QString,QString,QString,QString)),
        this,
        SLOT(handleFrontendAdded(QString,QString,QString,QString)));

    connect(
        m_dbusInterface,
        SIGNAL(frontendRemoved(QString)),
        this,
        SLOT(handleFrontendRemoved(QString)));

    connect(
        m_dbusInterface,
        SIGNAL(activeFrontendChanged(QString)),
        this,
        SLOT(handleActiveFrontendChanged(QString)));

    loadFrontends();
    loadActiveFrontend();
}

void MFrontendModel::loadFrontends()
{
    QDBusPendingCall call =
        m_dbusInterface->asyncCall("getFrontendList");

    auto *watcher =
        new QDBusPendingCallWatcher(call, this);

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        &MFrontendModel::handleFrontendListReply);
}

void MFrontendModel::loadActiveFrontend()
{
    QDBusPendingCall call =
        m_dbusInterface->asyncCall("activeFrontend");

    auto *watcher =
        new QDBusPendingCallWatcher(call, this);

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        [this](QDBusPendingCallWatcher *watcher) {
            QDBusPendingReply<QString> reply = *watcher;

            if (reply.isError()) {
                qDebug()
                    << "Failed to get initial active frontend:"
                    << reply.error().message();
            } else {
                handleGetActiveFrontend(reply.value());
            }

            watcher->deleteLater();
        });
}

int MFrontendModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);

    return m_frontends.size();
}

QVariant MFrontendModel::data(
    const QModelIndex &index,
    int role) const
{
    if (!index.isValid() ||
        index.row() < 0 ||
        index.row() >= m_frontends.size()) {
        return {};
    }

    const Frontend &frontend =
        m_frontends.at(index.row());

    switch (role) {
    case IdRole:
        return frontend.id;

    case NameRole:
        return frontend.name;

    case DescriptionRole:
        return frontend.description;

    case PathRole:
        return frontend.path;

    case ActiveRole:
        return frontend.active;

    default:
        return {};
    }
}

QHash<int, QByteArray> MFrontendModel::roleNames() const
{
    QHash<int, QByteArray> roles;

    roles[IdRole] = "frontendId";
    roles[NameRole] = "frontendName";
    roles[DescriptionRole] = "frontendDescription";
    roles[PathRole] = "frontendPath";
    roles[ActiveRole] = "frontendActive";

    return roles;
}

QString MFrontendModel::activeFrontend() const
{
    return m_activeFrontendIdMirror;
}

void MFrontendModel::setActiveFrontend(
    const QString &frontendId)
{
    if (frontendId.isEmpty()) {
        qDebug()
            << "Cannot switch to an empty frontend ID.";

        return;
    }

    bool frontendExists = false;

    for (const Frontend &frontend : m_frontends) {
        if (frontend.id == frontendId) {
            frontendExists = true;
            break;
        }
    }

    if (!frontendExists) {
        qDebug()
            << "Cannot switch to unknown frontend:"
            << frontendId;

        return;
    }

    if (frontendId == m_activeFrontendIdMirror) {
        return;
    }

    QDBusPendingCall call =
        m_dbusInterface->asyncCall(
            "setActiveFrontend",
            frontendId);

    auto *watcher =
        new QDBusPendingCallWatcher(call, this);

    connect(
        watcher,
        &QDBusPendingCallWatcher::finished,
        this,
        [watcher]() {
            if (watcher->isError()) {
                qDebug()
                    << "Failed to switch frontend:"
                    << watcher->error().message();
            }

            watcher->deleteLater();
        });
}

void MFrontendModel::handleFrontendListReply(
    QDBusPendingCallWatcher *watcher)
{
    QDBusPendingReply<QVariantList> reply = *watcher;

    if (reply.isError()) {
        qDebug()
            << "Failed to get frontend list:"
            << reply.error().message();

        watcher->deleteLater();
        return;
    }

    beginResetModel();

    m_frontends.clear();

    const QVariantList frontends = reply.value();

    for (const QVariant &frontendVar : frontends) {
        if (!frontendVar.canConvert<QDBusArgument>()) {
            qDebug()
                << "Unexpected frontend QVariant type:"
                << frontendVar.typeName();

            continue;
        }

        QDBusArgument dbusArg =
            frontendVar.value<QDBusArgument>();

        if (dbusArg.currentSignature() != "a{sv}") {
            qDebug()
                << "Unexpected D-Bus argument signature:"
                << dbusArg.currentSignature();

            continue;
        }

        QVariantMap map;
        dbusArg >> map;

        Frontend frontend;

        frontend.id =
            map.value("id").toString();

        frontend.name =
            map.value("name").toString();

        frontend.description =
            map.value("description").toString();

        frontend.path =
            map.value("path").toString();

        frontend.active =
            map.value("active").toBool();

        if (frontend.id.isEmpty()) {
            continue;
        }

        bool duplicate = false;

        for (const Frontend &existing : m_frontends) {
            if (existing.id == frontend.id) {
                duplicate = true;
                break;
            }
        }

        if (!duplicate) {
            m_frontends.append(frontend);
        }
    }

    if (!m_activeFrontendIdMirror.isEmpty()) {
        for (Frontend &frontend : m_frontends) {
            frontend.active =
                frontend.id == m_activeFrontendIdMirror;
        }
    }

    endResetModel();

    watcher->deleteLater();
}

void MFrontendModel::handleFrontendAdded(
    const QString &id,
    const QString &name,
    const QString &description,
    const QString &path)
{
    if (id.isEmpty()) {
        return;
    }

    for (const Frontend &frontend : m_frontends) {
        if (frontend.id == id) {
            return;
        }
    }

    Frontend frontend;

    frontend.id = id;
    frontend.name = name;
    frontend.description = description;
    frontend.path = path;
    frontend.active =
        (id == m_activeFrontendIdMirror);

    const int row = m_frontends.size();

    beginInsertRows(
        QModelIndex(),
        row,
        row);

    m_frontends.append(frontend);

    endInsertRows();
}

void MFrontendModel::handleFrontendRemoved(
    const QString &id)
{
    for (int i = 0;
         i < m_frontends.size();
         ++i) {

        if (m_frontends.at(i).id != id) {
            continue;
        }

        beginRemoveRows(
            QModelIndex(),
            i,
            i);

        m_frontends.removeAt(i);

        endRemoveRows();

        return;
    }
}

void MFrontendModel::handleActiveFrontendChanged(
    const QString &frontendId)
{
    updateActiveFrontendState(frontendId);
}

void MFrontendModel::handleGetActiveFrontend(
    const QString &frontendId)
{
    updateActiveFrontendState(frontendId);
}

void MFrontendModel::updateActiveFrontendState(
    const QString &frontendId)
{
    if (frontendId.isEmpty()) {
        return;
    }

    bool changed = false;

    for (int i = 0;
         i < m_frontends.size();
         ++i) {

        const bool newActive =
            m_frontends.at(i).id == frontendId;

        if (m_frontends[i].active != newActive) {
            m_frontends[i].active = newActive;

            emit dataChanged(
                index(i),
                index(i),
                {ActiveRole});

            changed = true;
        }
    }

    if (m_activeFrontendIdMirror != frontendId) {
        m_activeFrontendIdMirror = frontendId;

        emit activeFrontendChanged();

        changed = true;
    }

    Q_UNUSED(changed);
}
