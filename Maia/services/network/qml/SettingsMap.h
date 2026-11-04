#pragma once

// Connection settings and secrets as JavaScript objects, for QML editors:
//
//   { name, autoconnect, metered, availableToAll,
//     wifi: { ssid, ssidBytes, hidden, bssid, macAddress, clonedMac, clonedMacAddress },
//     security: { security, wepKeyIndex, wepPassphrase, leapUsername,
//                 eap: { method, identity, anonymousIdentity, caCertificate, noCaCertificate, domain,
//                        clientCertificate, privateKey, innerAuth, pacFile, peapVersion } },
//     ip4: { method, addresses: [{ address, prefix }], gateway, autoDns, dns: [], dnsSearch: [],
//            autoRoutes, routes: [{ destination, prefix, gateway, metric }], neverDefault },
//     ip6: { ... } }
//
// Enumerations are numbers (Network.IpMethod.Manual, ...). wifi.ssid is the name as text; the raw
// bytes (ssidBytes) are kept while the text is not changed, so a name that is not UTF-8 survives.
// Secrets: [{ key: Network.SecretKey.WifiPassword, value: "..." }].

#include "NetworkTypes.h"

#include <QVariantList>
#include <QVariantMap>

namespace MaiaNetwork {

QVariantMap settingsToMap(const ConnectionSettingsData &settings);
// Missing keys keep the defaults of a new profile
ConnectionSettingsData settingsFromMap(const QVariantMap &map);

QVariantList secretsToList(const QList<SecretData> &secrets);
QList<SecretData> secretsFromList(const QVariantList &list);

} // namespace MaiaNetwork
