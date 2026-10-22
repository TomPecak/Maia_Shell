#include "MFrontendModel.hpp"
#include "frontendmanager_interface.h"

#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>

namespace {
const QString serviceName = QStringLiteral("org.maia.FrontendManager");
const QString objectPath = QStringLiteral("/FrontendManager");
}

MFrontendModel::MFrontendModel(QObject *parent)
    : QAbstractListModel(parent)
{
    qDBusRegisterMetaType<QList<QVariantMap>>();

    // Generated proxy: unlike QDBusInterface it does not introspect the service in the constructor,
    // which was a blocking call to the server in the GUI thread
    m_manager = new FrontendManagerInterface(serviceName, objectPath, QDBusConnection::sessionBus(), this);

    // Signals first, then the state: a change between the two calls is not lost (D-Bus keeps the order
    // of the replies and signals of one service)
    connect(m_manager, &FrontendManagerInterface::activeFrontendChanged, this, &MFrontendModel::applyActiveFrontend);
    connect(m_manager, &FrontendManagerInterface::frontendAdded, this, &MFrontendModel::addFrontend);
    connect(m_manager, &FrontendManagerInterface::frontendRemoved, this, &MFrontendModel::removeFrontend);

    // The service may start after this process (or be restarted, once it runs in its own process):
    // load the state again whenever it appears on the bus
    m_serviceWatcher = new QDBusServiceWatcher(serviceName, QDBusConnection::sessionBus(),
                                               QDBusServiceWatcher::WatchForRegistration, this);
    connect(m_serviceWatcher, &QDBusServiceWatcher::serviceRegistered, this, &MFrontendModel::loadState);

    loadState();
}

MFrontendModel::~MFrontendModel() = default;

void MFrontendModel::loadState()
{
    auto *listWatcher = new QDBusPendingCallWatcher(m_manager->getFrontendList(), this);
    connect(listWatcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        QDBusPendingReply<QList<QVariantMap>> reply = *watcher;
        if (reply.isError())
            qDebug() << "[ERROR]" << __PRETTY_FUNCTION__ << "getFrontendList:" << reply.error().message();
        else
            applyFrontendList(reply.value());
        watcher->deleteLater();
    });

    auto *activeWatcher = new QDBusPendingCallWatcher(m_manager->activeFrontend(), this);
    connect(activeWatcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *watcher) {
        QDBusPendingReply<QString> reply = *watcher;
        if (reply.isError())
            qDebug() << "[ERROR]" << __PRETTY_FUNCTION__ << "activeFrontend:" << reply.error().message();
        else
            applyActiveFrontend(reply.value());
        watcher->deleteLater();
    });
}

MFrontendModel::Frontend MFrontendModel::frontendFromMap(const QVariantMap &map)
{
    Frontend frontend;
    frontend.id = map.value(QStringLiteral("id")).toString();
    frontend.name = map.value(QStringLiteral("name")).toString();
    frontend.description = map.value(QStringLiteral("description")).toString();
    frontend.path = map.value(QStringLiteral("path")).toString();
    frontend.rootPath = map.value(QStringLiteral("rootPath")).toString();
    frontend.active = map.value(QStringLiteral("active")).toBool();
    return frontend;
}

int MFrontendModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return m_frontends.size();
}

QVariant MFrontendModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_frontends.size())
        return QVariant();

    const Frontend &frontend = m_frontends[index.row()];
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
    case RootPathRole:
        return frontend.rootPath;
    default:
        return QVariant();
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
    roles[RootPathRole] = "frontendRootPath";
    return roles;
}

QString MFrontendModel::activeFrontend() const
{
    return m_activeFrontendIdMirror;
}

QString MFrontendModel::activeFrontendRootPath() const
{
    for (const Frontend &frontend : m_frontends) {
        if (frontend.id == m_activeFrontendIdMirror)
            return frontend.rootPath;
    }
    return {};
}

void MFrontendModel::setActiveFrontend(const QString &frontendId)
{
    auto *watcher = new QDBusPendingCallWatcher(m_manager->setActiveFrontend(frontendId), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [](QDBusPendingCallWatcher *watcher) {
        if (watcher->isError())
            qDebug() << "[ERROR] Failed to switch frontend:" << watcher->error().message();
        watcher->deleteLater();
    });
}

void MFrontendModel::applyFrontendList(const QList<QVariantMap> &frontends)
{
    beginResetModel();
    m_frontends.clear();
    QString activeFromList;
    for (const QVariantMap &map : frontends) {
        Frontend frontend = frontendFromMap(map);
        if (frontend.active)
            activeFromList = frontend.id;
        m_frontends.append(frontend);
    }
    // The active id already known (reply to activeFrontend or a signal) is newer than the flags in the list
    const QString activeId = m_activeFrontendIdMirror.isEmpty() ? activeFromList : m_activeFrontendIdMirror;
    for (Frontend &frontend : m_frontends)
        frontend.active = frontend.id == activeId;
    endResetModel();

    m_activeFrontendIdMirror = activeId;
    // also when the id did not change: activeFrontendRootPath is known only now
    Q_EMIT activeFrontendChanged();
}

void MFrontendModel::applyActiveFrontend(const QString &frontendId)
{
    if (m_activeFrontendIdMirror == frontendId)
        return;

    for (int i = 0; i < m_frontends.size(); ++i) {
        const bool newActive = m_frontends[i].id == frontendId;
        if (m_frontends[i].active != newActive) {
            m_frontends[i].active = newActive;
            Q_EMIT dataChanged(index(i), index(i), {ActiveRole});
        }
    }
    m_activeFrontendIdMirror = frontendId;
    Q_EMIT activeFrontendChanged();
}

void MFrontendModel::addFrontend(const QVariantMap &map)
{
    Frontend frontend = frontendFromMap(map);
    frontend.active = frontend.id == m_activeFrontendIdMirror;
    beginInsertRows(QModelIndex(), m_frontends.size(), m_frontends.size());
    m_frontends.append(frontend);
    endInsertRows();
}

void MFrontendModel::removeFrontend(const QString &frontendId)
{
    for (int i = 0; i < m_frontends.size(); ++i) {
        if (m_frontends[i].id == frontendId) {
            beginRemoveRows(QModelIndex(), i, i);
            m_frontends.removeAt(i);
            endRemoveRows();
            return;
        }
    }
}
