#pragma once

// The Wi-Fi adapters, for the Wi-Fi page (several adapters: one section each) and the details of
// the active connection (addresses, speed, band).

#include "QmlHelpers.h"

#include <QJSValue>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

class WifiDevicesModel : public SortedIdModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        DeviceIdRole = Qt::UserRole + 1,
        NameRole,               // "" with a single adapter
        StateRole,
        StateReasonRole,
        HwAddressRole,
        PermHwAddressRole,
        ActiveNetworkIdRole,
        ActiveConnectionUuidRole,
        HotspotRole,
        BitrateRole,            // kbit/s
        BandsRole,
        CanHotspotRole,
        ScanningRole,
        LastScanRole,           // Date
        Ip4AddressesRole,       // ["192.168.1.23/24"]
        Ip4GatewayRole,
        Ip4DnsRole,
        Ip6AddressesRole,
        Ip6GatewayRole,
        Ip6DnsRole,
    };
    Q_ENUM(Role)

    explicit WifiDevicesModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void disconnectDevice(const QString &deviceId, const QJSValue &callback = {});
    Q_INVOKABLE void scan(const QString &deviceId, const QJSValue &callback = {});
    Q_INVOKABLE QVariantMap get(const QString &deviceId) const;

private:
    void resort();

    NetworkSource *m_source;
};

} // namespace MaiaNetwork
