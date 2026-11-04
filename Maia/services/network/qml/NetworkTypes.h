#pragma once

// Plain values of the network state, copied out of Cap'n Proto messages (NetworkConnection) and
// kept in the GUI thread (NetworkState), plus the enumerations QML sees as Network.Security,
// Network.DeviceState, ... with the values of contract/network.capnp.

#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

// Enumerations of the contract, for QML: Network.Security.WpaPersonal, ...
class Network
{
    Q_GADGET
    QML_NAMED_ELEMENT(Network)
    QML_UNCREATABLE("Network only holds enumerations")

public:
    enum class Connectivity { Unknown, None, Portal, Limited, Full };
    Q_ENUM(Connectivity)

    enum class Permission { No, Auth, Yes };
    Q_ENUM(Permission)

    enum class ConnectionType { None, Wifi, Ethernet, Vpn, Other };
    Q_ENUM(ConnectionType)

    enum class DeviceState { Unknown, Unmanaged, Unavailable, Disconnected, Connecting, NeedAuth, Connected, Disconnecting, Failed };
    Q_ENUM(DeviceState)

    enum class StateReason {
        None,
        Other,
        NoSecrets,
        WrongSecrets,
        SupplicantFailed,
        SupplicantTimeout,
        ConfigFailed,
        IpConfigFailed,
        IpConfigExpired,
        ConnectionRemoved,
        SsidNotFound,
        FirmwareMissing,
        UserRequested,
        CarrierLost
    };
    Q_ENUM(StateReason)

    enum class Security { None, EnhancedOpen, Wep, Leap, WpaPersonal, Wpa3Personal, WpaEnterprise, Wpa3Enterprise };
    Q_ENUM(Security)

    enum class Metered { Unknown, Yes, No };
    Q_ENUM(Metered)

    enum class SecretKey { WifiPassword, WepKey, LeapPassword, EapPassword, EapPrivateKeyPassword, EapIdentity };
    Q_ENUM(SecretKey)

    enum class Validation { NotEmpty, WpaPassword, WepKey, WepPassphrase };
    Q_ENUM(Validation)

    enum class ErrorCode { None, NotFound, NotAllowed, InvalidArgument, NotSupported, Unavailable, Failed };
    Q_ENUM(ErrorCode)

    // Bits of `bands`
    enum Band { Band24GHz = 0x1, Band5GHz = 0x2, Band6GHz = 0x4 };
    Q_ENUM(Band)

    // Whether a network of this security asks for a password (Enhanced Open does not: no padlock)
    static bool isSecure(Security security) { return security != Security::None && security != Security::EnhancedOpen; }
    static bool isEnterprise(Security security)
    {
        return security == Security::WpaEnterprise || security == Security::Wpa3Enterprise;
    }

    // The signal level of a strength 0..100, as GNOME's icons: 0 none, 1 weak, 2 ok, 3 good, 4 excellent
    static int signalLevel(int strength)
    {
        return strength < 20 ? 0 : strength < 40 ? 1 : strength < 50 ? 2 : strength < 80 ? 3 : 4;
    }

    // The checks of the password dialog (the same rules as the service and GNOME)
    static bool accepts(Validation validation, const QString &value);
};

struct IpInfo {
    QStringList addresses;   // "192.168.1.23/24"
    QString gateway;
    QStringList dns;
    bool operator==(const IpInfo &) const = default;
};

struct Permissions {
    Network::Permission enableDisableWifi = Network::Permission::No;
    Network::Permission networkControl = Network::Permission::No;
    Network::Permission modifyOwn = Network::Permission::No;
    Network::Permission modifySystem = Network::Permission::No;
    Network::Permission wifiShareOpen = Network::Permission::No;
    Network::Permission wifiShareProtected = Network::Permission::No;
    bool operator==(const Permissions &) const = default;
};

struct StatusData {
    bool running = false;
    bool networkingEnabled = false;
    bool wirelessEnabled = false;
    bool wirelessHardwareEnabled = false;
    Network::Connectivity connectivity = Network::Connectivity::Unknown;
    QString connectivityCheckUri;
    Network::ConnectionType primaryType = Network::ConnectionType::None;
    QString primaryName;
    QString primaryUuid;
    QString primaryDeviceId;
    bool primaryActivating = false;
    Permissions permissions;
    bool operator==(const StatusData &) const = default;
};

struct DeviceData {
    QString id;
    QString name;
    QString hwAddress;
    QString permHwAddress;
    Network::DeviceState state = Network::DeviceState::Unknown;
    Network::StateReason stateReason = Network::StateReason::None;
    QString activeNetworkId;
    QString activeConnectionUuid;
    bool hotspot = false;
    quint32 bitrate = 0;     // kbit/s
    int bands = 0;
    bool canHotspot = false;
    bool scanning = false;
    qint64 lastScan = 0;     // ms since 1970
    IpInfo ip4;
    IpInfo ip6;
    bool operator==(const DeviceData &) const = default;
};

struct AccessPointData {
    QString bssid;
    int strength = 0;
    quint32 frequency = 0;
    quint32 maxBitrate = 0;
    qint64 lastSeen = 0;
    bool operator==(const AccessPointData &) const = default;
};

struct NetworkData {
    QString id;
    QString deviceId;
    QByteArray ssid;
    QString name;
    Network::Security security = Network::Security::None;
    int strength = 0;
    quint32 frequency = 0;
    int bands = 0;
    QStringList connectionUuids;
    bool active = false;
    QList<AccessPointData> accessPoints;
    bool operator==(const NetworkData &) const = default;
};

struct ConnectionData {
    QString uuid;
    QString name;
    QByteArray ssid;
    QString ssidText;
    Network::Security security = Network::Security::None;
    bool hidden = false;
    bool hotspot = false;
    bool autoconnect = true;
    Network::Metered metered = Network::Metered::Unknown;
    bool availableToAll = false;
    qint64 lastUsed = 0;
    QString activeDeviceId;
    bool qrSupported = false;
    bool operator==(const ConnectionData &) const = default;
};

struct SecretFieldData {
    Network::SecretKey key = Network::SecretKey::WifiPassword;
    QString value;
    bool hidden = true;
    Network::Validation validation = Network::Validation::NotEmpty;
};

struct SecretRequestData {
    QString id;
    QString connectionUuid;
    QString name;
    QString deviceId;
    Network::Security security = Network::Security::None;
    QList<SecretFieldData> fields;
    bool retry = false;
    bool wpsPushButton = false;
};

struct SecretData {
    Network::SecretKey key;
    QString value;
};

// The answer of a control call
struct Result {
    Network::ErrorCode error = Network::ErrorCode::None;
    QString message;
};

} // namespace MaiaNetwork
