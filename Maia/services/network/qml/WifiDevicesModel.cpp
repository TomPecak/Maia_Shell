#include "WifiDevicesModel.h"

#include <QDateTime>
#include <algorithm>

namespace MaiaNetwork {

WifiDevicesModel::WifiDevicesModel(QObject *parent)
    : SortedIdModel(parent)
    , m_source(NetworkSource::instance())
{
    auto resortAll = [this] { resort(); };
    connect(m_source, &NetworkSource::reset, this, resortAll);
    connect(m_source, &NetworkSource::deviceRemoved, this, resortAll);
    connect(m_source, &NetworkSource::deviceChanged, this, [this](const QString &id) {
        this->resort();
        rowChanged(id);
    });
    this->resort();
}

void WifiDevicesModel::resort()
{
    QStringList order = m_source->devices().keys();
    std::sort(order.begin(), order.end());
    sync(order);
}

QVariant WifiDevicesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
        return {};
    const auto *d = m_source->device(ids().at(index.row()));
    if (!d)
        return {};
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return d->name;
    case DeviceIdRole:
        return d->id;
    case StateRole:
        return QVariant::fromValue(d->state);
    case StateReasonRole:
        return QVariant::fromValue(d->stateReason);
    case HwAddressRole:
        return d->hwAddress;
    case PermHwAddressRole:
        return d->permHwAddress;
    case ActiveNetworkIdRole:
        return d->activeNetworkId;
    case ActiveConnectionUuidRole:
        return d->activeConnectionUuid;
    case HotspotRole:
        return d->hotspot;
    case BitrateRole:
        return d->bitrate;
    case BandsRole:
        return d->bands;
    case CanHotspotRole:
        return d->canHotspot;
    case ScanningRole:
        return d->scanning;
    case LastScanRole:
        return d->lastScan > 0 ? QDateTime::fromMSecsSinceEpoch(d->lastScan) : QDateTime();
    case Ip4AddressesRole:
        return d->ip4.addresses;
    case Ip4GatewayRole:
        return d->ip4.gateway;
    case Ip4DnsRole:
        return d->ip4.dns;
    case Ip6AddressesRole:
        return d->ip6.addresses;
    case Ip6GatewayRole:
        return d->ip6.gateway;
    case Ip6DnsRole:
        return d->ip6.dns;
    }
    return {};
}

QHash<int, QByteArray> WifiDevicesModel::roleNames() const
{
    return {
        {DeviceIdRole, "deviceId"},
        {NameRole, "name"},
        {StateRole, "state"},
        {StateReasonRole, "stateReason"},
        {HwAddressRole, "hwAddress"},
        {PermHwAddressRole, "permHwAddress"},
        {ActiveNetworkIdRole, "activeNetworkId"},
        {ActiveConnectionUuidRole, "activeConnectionUuid"},
        {HotspotRole, "hotspot"},
        {BitrateRole, "bitrate"},
        {BandsRole, "bands"},
        {CanHotspotRole, "canHotspot"},
        {ScanningRole, "scanning"},
        {LastScanRole, "lastScan"},
        {Ip4AddressesRole, "ip4Addresses"},
        {Ip4GatewayRole, "ip4Gateway"},
        {Ip4DnsRole, "ip4Dns"},
        {Ip6AddressesRole, "ip6Addresses"},
        {Ip6GatewayRole, "ip6Gateway"},
        {Ip6DnsRole, "ip6Dns"},
    };
}

void WifiDevicesModel::disconnectDevice(const QString &deviceId, const QJSValue &callback)
{
    m_source->disconnectDevice(deviceId, jsCallback(this, callback));
}

void WifiDevicesModel::scan(const QString &deviceId, const QJSValue &callback)
{
    m_source->requestScan(deviceId, jsCallback(this, callback));
}

QVariantMap WifiDevicesModel::get(const QString &deviceId) const
{
    const qsizetype row = ids().indexOf(deviceId);
    if (row < 0)
        return {};
    QVariantMap values;
    const auto names = roleNames();
    for (auto it = names.cbegin(); it != names.cend(); ++it)
        values.insert(QString::fromUtf8(it.value()), data(index(int(row)), it.key()));
    return values;
}

} // namespace MaiaNetwork
