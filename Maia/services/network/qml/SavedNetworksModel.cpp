#include "SavedNetworksModel.h"

#include <QCollator>
#include <QDateTime>
#include <algorithm>

namespace MaiaNetwork {

SavedNetworksModel::SavedNetworksModel(QObject *parent)
    : SortedIdModel(parent)
    , m_source(NetworkSource::instance())
{
    auto resortAll = [this] { resort(); };
    connect(m_source, &NetworkSource::reset, this, resortAll);
    connect(m_source, &NetworkSource::connectionRemoved, this, resortAll);
    connect(m_source, &NetworkSource::connectionChanged, this, [this](const QString &uuid) {
        this->resort();
        rowChanged(uuid);
    });
    // In reach and signal strength follow the networks
    auto all = [this] {
        for (const auto &uuid : ids())
            rowChanged(uuid);
    };
    connect(m_source, &NetworkSource::networkChanged, this, all);
    connect(m_source, &NetworkSource::networkRemoved, this, all);
    this->resort();
}

void SavedNetworksModel::resort()
{
    QList<const ConnectionData *> connections;
    for (const auto &connection : m_source->connections()) {
        if (!connection.hotspot)
            connections.append(&connection);
    }
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(connections.begin(), connections.end(), [&](const ConnectionData *a, const ConnectionData *b) {
        if (a->lastUsed != b->lastUsed)
            return a->lastUsed > b->lastUsed;
        const int byName = collator.compare(a->name, b->name);
        return byName != 0 ? byName < 0 : a->uuid < b->uuid;
    });
    QStringList order;
    for (const auto *connection : connections)
        order.append(connection->uuid);
    sync(order);
}

const NetworkData *SavedNetworksModel::networkOf(const QString &uuid) const
{
    const NetworkData *best = nullptr;
    for (const auto &network : m_source->networks()) {
        if (network.connectionUuids.contains(uuid) && (!best || network.strength > best->strength))
            best = &network;
    }
    return best;
}

QVariant SavedNetworksModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
        return {};
    const auto *c = m_source->connection(ids().at(index.row()));
    if (!c)
        return {};
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return c->name;
    case UuidRole:
        return c->uuid;
    case SsidRole:
        return c->ssidText;
    case SecurityRole:
        return QVariant::fromValue(c->security);
    case SecureRole:
        return Network::isSecure(c->security);
    case HiddenRole:
        return c->hidden;
    case AutoconnectRole:
        return c->autoconnect;
    case MeteredRole:
        return QVariant::fromValue(c->metered);
    case AvailableToAllRole:
        return c->availableToAll;
    case LastUsedRole:
        return c->lastUsed > 0 ? QDateTime::fromMSecsSinceEpoch(c->lastUsed) : QDateTime();
    case ActiveRole:
        return !c->activeDeviceId.isEmpty();
    case ActiveDeviceIdRole:
        return c->activeDeviceId;
    case InRangeRole:
        return networkOf(c->uuid) != nullptr;
    case StrengthRole: {
        const auto *network = networkOf(c->uuid);
        return network ? network->strength : 0;
    }
    case SignalLevelRole: {
        const auto *network = networkOf(c->uuid);
        return network ? Network::signalLevel(network->strength) : 0;
    }
    case QrSupportedRole:
        return c->qrSupported;
    }
    return {};
}

QHash<int, QByteArray> SavedNetworksModel::roleNames() const
{
    return {
        {UuidRole, "uuid"},
        {NameRole, "name"},
        {SsidRole, "ssid"},
        {SecurityRole, "security"},
        {SecureRole, "secure"},
        {HiddenRole, "hidden"},
        {AutoconnectRole, "autoconnect"},
        {MeteredRole, "metered"},
        {AvailableToAllRole, "availableToAll"},
        {LastUsedRole, "lastUsed"},
        {ActiveRole, "active"},
        {ActiveDeviceIdRole, "activeDeviceId"},
        {InRangeRole, "inRange"},
        {StrengthRole, "strength"},
        {SignalLevelRole, "signalLevel"},
        {QrSupportedRole, "qrSupported"},
    };
}

void SavedNetworksModel::forget(const QString &uuid, const QJSValue &callback)
{
    m_source->forget(uuid, jsCallback(this, callback));
}

void SavedNetworksModel::activate(const QString &uuid, const QString &deviceId, const QJSValue &callback)
{
    m_source->activate(uuid, deviceId, jsCallback(this, callback));
}

QVariantMap SavedNetworksModel::get(const QString &uuid) const
{
    const qsizetype row = ids().indexOf(uuid);
    if (row < 0)
        return {};
    QVariantMap values;
    const auto names = roleNames();
    for (auto it = names.cbegin(); it != names.cend(); ++it)
        values.insert(QString::fromUtf8(it.value()), data(index(int(row)), it.key()));
    return values;
}

} // namespace MaiaNetwork
