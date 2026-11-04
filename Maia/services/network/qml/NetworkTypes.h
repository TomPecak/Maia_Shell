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
namespace Network
{
Q_NAMESPACE
QML_NAMED_ELEMENT(Network)
// Always Network.Security.None, never Network.None: several enumerations share value names
Q_CLASSINFO("RegisterEnumClassesUnscoped", "false")

    enum class Connectivity { Unknown, None, Portal, Limited, Full };
    Q_ENUM_NS(Connectivity)

    enum class Permission { No, Auth, Yes };
    Q_ENUM_NS(Permission)

    enum class ConnectionType { None, Wifi, Ethernet, Vpn, Other };
    Q_ENUM_NS(ConnectionType)

    enum class DeviceState { Unknown, Unmanaged, Unavailable, Disconnected, Connecting, NeedAuth, Connected, Disconnecting, Failed };
    Q_ENUM_NS(DeviceState)

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
    Q_ENUM_NS(StateReason)

    enum class Security { None, EnhancedOpen, Wep, Leap, WpaPersonal, Wpa3Personal, WpaEnterprise, Wpa3Enterprise };
    Q_ENUM_NS(Security)

    enum class Metered { Unknown, Yes, No };
    Q_ENUM_NS(Metered)

    enum class SecretKey { WifiPassword, WepKey, LeapPassword, EapPassword, EapPrivateKeyPassword, EapIdentity };
    Q_ENUM_NS(SecretKey)

    enum class Validation { NotEmpty, WpaPassword, WepKey, WepPassphrase };
    Q_ENUM_NS(Validation)

    enum class ErrorCode { None, NotFound, NotAllowed, InvalidArgument, NotSupported, Unavailable, Failed };
    Q_ENUM_NS(ErrorCode)

    // Connection settings (the details editor)
    enum class IpMethod { Auto, DhcpOnly, Manual, LinkLocal, Shared, Disabled };
    Q_ENUM_NS(IpMethod)

    enum class ClonedMac { Default, Preserve, Permanent, Random, Stable, StableSsid, Address };
    Q_ENUM_NS(ClonedMac)

    enum class EapMethod { Tls, Peap, Ttls, Pwd, Fast, Leap };
    Q_ENUM_NS(EapMethod)

    enum class InnerAuth { Mschapv2, Mschap, Pap, Chap, Gtc, Md5 };
    Q_ENUM_NS(InnerAuth)

    // Bits of `bands`
    enum Band { Band24GHz = 0x1, Band5GHz = 0x2, Band6GHz = 0x4 };
    Q_ENUM_NS(Band)

    // Whether a network of this security asks for a password (Enhanced Open does not: no padlock)
    inline bool isSecure(Security security) { return security != Security::None && security != Security::EnhancedOpen; }
    inline bool isEnterprise(Security security)
    {
        return security == Security::WpaEnterprise || security == Security::Wpa3Enterprise;
    }

    // The signal level of a strength 0..100, as GNOME's icons: 0 none, 1 weak, 2 ok, 3 good, 4 excellent
    inline int signalLevel(int strength)
    {
        return strength < 20 ? 0 : strength < 40 ? 1 : strength < 50 ? 2 : strength < 80 ? 3 : 4;
    }

    // The checks of the password dialog (the same rules as the service and GNOME)
    bool accepts(Validation validation, const QString &value);
} // namespace Network

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
    bool operator==(const SecretData &) const = default;
};

// --- Connection settings (contract: ConnectionSettings), defaults as a new profile has them ---

struct IpAddressData {
    QString address;
    int prefix = 0;
    bool operator==(const IpAddressData &) const = default;
};

struct RouteData {
    QString destination;
    int prefix = 0;
    QString gateway;
    qint64 metric = -1;      // -1 = default
    bool operator==(const RouteData &) const = default;
};

struct IpSettingsData {
    Network::IpMethod method = Network::IpMethod::Auto;
    QList<IpAddressData> addresses;
    QString gateway;
    bool autoDns = true;
    QStringList dns;
    QStringList dnsSearch;
    bool autoRoutes = true;
    QList<RouteData> routes;
    bool neverDefault = false;
    bool operator==(const IpSettingsData &) const = default;
};

struct WifiSettingsData {
    QByteArray ssid;
    bool hidden = false;
    QString bssid;
    QString macAddress;
    Network::ClonedMac clonedMac = Network::ClonedMac::Default;
    QString clonedMacAddress;
    bool operator==(const WifiSettingsData &) const = default;
};

struct EapSettingsData {
    Network::EapMethod method = Network::EapMethod::Peap;
    QString identity;
    QString anonymousIdentity;
    QString caCertificate;
    bool noCaCertificate = false;
    QString domain;
    QString clientCertificate;
    QString privateKey;
    Network::InnerAuth innerAuth = Network::InnerAuth::Mschapv2;
    QString pacFile;
    int peapVersion = -1;    // -1 = automatic
    bool operator==(const EapSettingsData &) const = default;
};

struct SecuritySettingsData {
    Network::Security security = Network::Security::None;
    int wepKeyIndex = 0;
    bool wepPassphrase = false;
    QString leapUsername;
    EapSettingsData eap;
    bool operator==(const SecuritySettingsData &) const = default;
};

struct ConnectionSettingsData {
    QString name;
    bool autoconnect = true;
    Network::Metered metered = Network::Metered::Unknown;
    bool availableToAll = false;
    WifiSettingsData wifi;
    SecuritySettingsData security;
    IpSettingsData ip4;
    IpSettingsData ip6;
    bool operator==(const ConnectionSettingsData &) const = default;
};

// A QR code to share a network: its text and size x size modules, row by row, 1 = dark
struct QrCodeData {
    QString text;
    int size = 0;
    QByteArray modules;
};

// The answer of a control call
struct Result {
    Network::ErrorCode error = Network::ErrorCode::None;
    QString message;
};

} // namespace MaiaNetwork
