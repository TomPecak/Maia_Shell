#include "SettingsMap.h"

namespace MaiaNetwork {

namespace {

template<typename E>
E enumOf(const QVariantMap &map, const char *key, E fallback)
{
    const QVariant value = map.value(QLatin1String(key));
    return value.isValid() ? static_cast<E>(value.toInt()) : fallback;
}

QString textOf(const QVariantMap &map, const char *key, const QString &fallback = {})
{
    const QVariant value = map.value(QLatin1String(key));
    return value.isValid() ? value.toString() : fallback;
}

bool flagOf(const QVariantMap &map, const char *key, bool fallback)
{
    const QVariant value = map.value(QLatin1String(key));
    return value.isValid() ? value.toBool() : fallback;
}

QVariantMap ipToMap(const IpSettingsData &ip)
{
    QVariantList addresses;
    for (const auto &a : ip.addresses)
        addresses.append(QVariantMap{{QStringLiteral("address"), a.address}, {QStringLiteral("prefix"), a.prefix}});
    QVariantList routes;
    for (const auto &r : ip.routes) {
        routes.append(QVariantMap{{QStringLiteral("destination"), r.destination},
                                  {QStringLiteral("prefix"), r.prefix},
                                  {QStringLiteral("gateway"), r.gateway},
                                  {QStringLiteral("metric"), r.metric}});
    }
    return {
        {QStringLiteral("method"), int(ip.method)},
        {QStringLiteral("addresses"), addresses},
        {QStringLiteral("gateway"), ip.gateway},
        {QStringLiteral("autoDns"), ip.autoDns},
        {QStringLiteral("dns"), ip.dns},
        {QStringLiteral("dnsSearch"), ip.dnsSearch},
        {QStringLiteral("autoRoutes"), ip.autoRoutes},
        {QStringLiteral("routes"), routes},
        {QStringLiteral("neverDefault"), ip.neverDefault},
    };
}

IpSettingsData ipFromMap(const QVariantMap &map)
{
    IpSettingsData ip;
    ip.method = enumOf(map, "method", ip.method);
    for (const auto &item : map.value(QStringLiteral("addresses")).toList()) {
        const auto a = item.toMap();
        ip.addresses.append(IpAddressData{a.value(QStringLiteral("address")).toString().trimmed(), a.value(QStringLiteral("prefix")).toInt()});
    }
    ip.gateway = textOf(map, "gateway").trimmed();
    ip.autoDns = flagOf(map, "autoDns", ip.autoDns);
    ip.dns = map.value(QStringLiteral("dns")).toStringList();
    ip.dnsSearch = map.value(QStringLiteral("dnsSearch")).toStringList();
    ip.autoRoutes = flagOf(map, "autoRoutes", ip.autoRoutes);
    for (const auto &item : map.value(QStringLiteral("routes")).toList()) {
        const auto r = item.toMap();
        const QVariant metric = r.value(QStringLiteral("metric"));
        ip.routes.append(RouteData{r.value(QStringLiteral("destination")).toString().trimmed(), r.value(QStringLiteral("prefix")).toInt(),
                                   r.value(QStringLiteral("gateway")).toString().trimmed(), metric.isValid() ? metric.toLongLong() : -1});
    }
    ip.neverDefault = flagOf(map, "neverDefault", ip.neverDefault);
    return ip;
}

} // namespace

QVariantMap settingsToMap(const ConnectionSettingsData &s)
{
    const auto &w = s.wifi;
    const auto &e = s.security.eap;
    const QVariantMap eap{
        {QStringLiteral("method"), int(e.method)},
        {QStringLiteral("identity"), e.identity},
        {QStringLiteral("anonymousIdentity"), e.anonymousIdentity},
        {QStringLiteral("caCertificate"), e.caCertificate},
        {QStringLiteral("noCaCertificate"), e.noCaCertificate},
        {QStringLiteral("domain"), e.domain},
        {QStringLiteral("clientCertificate"), e.clientCertificate},
        {QStringLiteral("privateKey"), e.privateKey},
        {QStringLiteral("innerAuth"), int(e.innerAuth)},
        {QStringLiteral("pacFile"), e.pacFile},
        {QStringLiteral("peapVersion"), e.peapVersion},
    };
    return {
        {QStringLiteral("name"), s.name},
        {QStringLiteral("autoconnect"), s.autoconnect},
        {QStringLiteral("metered"), int(s.metered)},
        {QStringLiteral("availableToAll"), s.availableToAll},
        {QStringLiteral("wifi"),
         QVariantMap{
             {QStringLiteral("ssid"), QString::fromUtf8(w.ssid)},
             {QStringLiteral("ssidBytes"), w.ssid},
             {QStringLiteral("hidden"), w.hidden},
             {QStringLiteral("bssid"), w.bssid},
             {QStringLiteral("macAddress"), w.macAddress},
             {QStringLiteral("clonedMac"), int(w.clonedMac)},
             {QStringLiteral("clonedMacAddress"), w.clonedMacAddress},
         }},
        {QStringLiteral("security"),
         QVariantMap{
             {QStringLiteral("security"), int(s.security.security)},
             {QStringLiteral("wepKeyIndex"), s.security.wepKeyIndex},
             {QStringLiteral("wepPassphrase"), s.security.wepPassphrase},
             {QStringLiteral("leapUsername"), s.security.leapUsername},
             {QStringLiteral("eap"), eap},
         }},
        {QStringLiteral("ip4"), ipToMap(s.ip4)},
        {QStringLiteral("ip6"), ipToMap(s.ip6)},
    };
}

ConnectionSettingsData settingsFromMap(const QVariantMap &map)
{
    ConnectionSettingsData s;
    s.name = textOf(map, "name").trimmed();
    s.autoconnect = flagOf(map, "autoconnect", s.autoconnect);
    s.metered = enumOf(map, "metered", s.metered);
    s.availableToAll = flagOf(map, "availableToAll", s.availableToAll);

    const auto w = map.value(QStringLiteral("wifi")).toMap();
    const QString ssid = textOf(w, "ssid");
    const QByteArray ssidBytes = w.value(QStringLiteral("ssidBytes")).toByteArray();
    s.wifi.ssid = !ssidBytes.isEmpty() && QString::fromUtf8(ssidBytes) == ssid ? ssidBytes : ssid.toUtf8();
    s.wifi.hidden = flagOf(w, "hidden", false);
    s.wifi.bssid = textOf(w, "bssid").trimmed().toUpper();
    s.wifi.macAddress = textOf(w, "macAddress").trimmed().toUpper();
    s.wifi.clonedMac = enumOf(w, "clonedMac", s.wifi.clonedMac);
    s.wifi.clonedMacAddress = textOf(w, "clonedMacAddress").trimmed().toUpper();

    const auto sec = map.value(QStringLiteral("security")).toMap();
    s.security.security = enumOf(sec, "security", s.security.security);
    s.security.wepKeyIndex = qBound(0, sec.value(QStringLiteral("wepKeyIndex")).toInt(), 3);
    s.security.wepPassphrase = flagOf(sec, "wepPassphrase", false);
    s.security.leapUsername = textOf(sec, "leapUsername");
    const auto e = sec.value(QStringLiteral("eap")).toMap();
    auto &eap = s.security.eap;
    eap.method = enumOf(e, "method", eap.method);
    eap.identity = textOf(e, "identity");
    eap.anonymousIdentity = textOf(e, "anonymousIdentity");
    eap.caCertificate = textOf(e, "caCertificate");
    eap.noCaCertificate = flagOf(e, "noCaCertificate", false);
    eap.domain = textOf(e, "domain").trimmed();
    eap.clientCertificate = textOf(e, "clientCertificate");
    eap.privateKey = textOf(e, "privateKey");
    eap.innerAuth = enumOf(e, "innerAuth", eap.innerAuth);
    eap.pacFile = textOf(e, "pacFile");
    const QVariant peap = e.value(QStringLiteral("peapVersion"));
    eap.peapVersion = peap.isValid() ? qBound(-1, peap.toInt(), 1) : -1;

    s.ip4 = ipFromMap(map.value(QStringLiteral("ip4")).toMap());
    s.ip6 = ipFromMap(map.value(QStringLiteral("ip6")).toMap());
    return s;
}

QVariantList secretsToList(const QList<SecretData> &secrets)
{
    QVariantList list;
    for (const auto &secret : secrets)
        list.append(QVariantMap{{QStringLiteral("key"), int(secret.key)}, {QStringLiteral("value"), secret.value}});
    return list;
}

QList<SecretData> secretsFromList(const QVariantList &list)
{
    QList<SecretData> secrets;
    for (const auto &item : list) {
        const auto map = item.toMap();
        secrets.append(SecretData{static_cast<Network::SecretKey>(map.value(QStringLiteral("key")).toInt()),
                                  map.value(QStringLiteral("value")).toString()});
    }
    return secrets;
}

} // namespace MaiaNetwork
