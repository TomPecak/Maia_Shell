#include "WifiNetworksModel.h"

#include <QCollator>
#include <algorithm>

namespace MaiaNetwork {

WifiNetworksModel::WifiNetworksModel(QObject *parent)
    : SortedIdModel(parent)
    , m_source(NetworkSource::instance())
{
    auto resortAll = [this] { resort(); };
    connect(m_source, &NetworkSource::reset, this, resortAll);
    connect(m_source, &NetworkSource::networkRemoved, this, resortAll);
    connect(m_source, &NetworkSource::connectionChanged, this, resortAll);
    connect(m_source, &NetworkSource::connectionRemoved, this, resortAll);
    connect(m_source, &NetworkSource::networkChanged, this, [this](const QString &id) {
        this->resort();
        rowChanged(id);
    });
    // The device's state decides "connecting" and the active network
    connect(m_source, &NetworkSource::deviceChanged, this, [this](const QString &) {
        this->resort();
        for (const auto &id : ids())
            rowChanged(id);
    });
    connect(m_source, &NetworkSource::deviceRemoved, this, resortAll);
    this->resort();
}

void WifiNetworksModel::setDeviceId(const QString &deviceId)
{
    if (m_deviceId == deviceId)
        return;
    m_deviceId = deviceId;
    resort();
    Q_EMIT deviceIdChanged();
}

void WifiNetworksModel::setLimit(int limit)
{
    if (m_limit == limit)
        return;
    m_limit = limit;
    resort();
    Q_EMIT limitChanged();
}

bool WifiNetworksModel::connectingTo(const NetworkData &network) const
{
    const auto *device = m_source->device(network.deviceId);
    return device && device->activeNetworkId == network.id
        && (device->state == Network::DeviceState::Connecting || device->state == Network::DeviceState::NeedAuth);
}

void WifiNetworksModel::resort()
{
    QList<const NetworkData *> networks;
    for (const auto &network : m_source->networks()) {
        if (m_deviceId.isEmpty() || network.deviceId == m_deviceId)
            networks.append(&network);
    }
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(networks.begin(), networks.end(), [&](const NetworkData *a, const NetworkData *b) {
        if (a->active != b->active)
            return a->active;
        const bool aKnown = !a->connectionUuids.isEmpty(), bKnown = !b->connectionUuids.isEmpty();
        if (aKnown != bKnown)
            return aKnown;
        if (a->strength != b->strength)
            return a->strength > b->strength;
        const bool aSecure = Network::isSecure(a->security), bSecure = Network::isSecure(b->security);
        if (aSecure != bSecure)
            return aSecure;
        const int byName = collator.compare(a->name, b->name);
        return byName != 0 ? byName < 0 : a->id < b->id;
    });
    QStringList order;
    for (const auto *network : networks) {
        if (m_limit > 0 && order.size() >= m_limit)
            break;
        order.append(network->id);
    }
    sync(order);
}

QVariant WifiNetworksModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
        return {};
    const auto *network = m_source->network(ids().at(index.row()));
    if (!network)
        return {};
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return network->name;
    case NetworkIdRole:
        return network->id;
    case DeviceIdRole:
        return network->deviceId;
    case SecurityRole:
        return QVariant::fromValue(network->security);
    case SecureRole:
        return Network::isSecure(network->security);
    case EnterpriseRole:
        return Network::isEnterprise(network->security);
    case StrengthRole:
        return network->strength;
    case SignalLevelRole:
        return Network::signalLevel(network->strength);
    case FrequencyRole:
        return network->frequency;
    case BandsRole:
        return network->bands;
    case KnownRole:
        return !network->connectionUuids.isEmpty();
    case ConnectionUuidRole:
        return network->connectionUuids.value(0);
    case ActiveRole:
        return network->active;
    case ConnectingRole:
        return connectingTo(*network);
    }
    return {};
}

QHash<int, QByteArray> WifiNetworksModel::roleNames() const
{
    return {
        {NetworkIdRole, "networkId"},
        {NameRole, "name"},
        {DeviceIdRole, "deviceId"},
        {SecurityRole, "security"},
        {SecureRole, "secure"},
        {EnterpriseRole, "enterprise"},
        {StrengthRole, "strength"},
        {SignalLevelRole, "signalLevel"},
        {FrequencyRole, "frequency"},
        {BandsRole, "bands"},
        {KnownRole, "known"},
        {ConnectionUuidRole, "connectionUuid"},
        {ActiveRole, "active"},
        {ConnectingRole, "connecting"},
    };
}

void WifiNetworksModel::connectNetwork(const QString &networkId, const QJSValue &callback)
{
    m_source->connectNetwork(networkId, jsCallback(this, callback));
}

QVariantMap WifiNetworksModel::get(const QString &networkId) const
{
    const qsizetype row = ids().indexOf(networkId);
    if (row < 0)
        return {};
    QVariantMap values;
    const auto names = roleNames();
    for (auto it = names.cbegin(); it != names.cend(); ++it)
        values.insert(QString::fromUtf8(it.value()), data(index(int(row)), it.key()));
    return values;
}

} // namespace MaiaNetwork
