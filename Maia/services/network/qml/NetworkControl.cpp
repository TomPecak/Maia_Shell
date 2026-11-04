#include "NetworkControl.h"

#include "SettingsMap.h"

#include <QJSEngine>
#include <QPointer>
#include <QRegularExpression>
#include <QSysInfo>

#include <arpa/inet.h>

namespace MaiaNetwork {

NetworkControl::NetworkControl(QObject *parent)
    : QObject(parent)
    , m_source(NetworkSource::instance())
{
    connect(m_source, &NetworkSource::statusChanged, this, &NetworkControl::changed);
    connect(m_source, &NetworkSource::reset, this, &NetworkControl::changed);
    connect(m_source, &NetworkSource::deviceChanged, this, &NetworkControl::changed);
    connect(m_source, &NetworkSource::deviceRemoved, this, &NetworkControl::changed);
}

bool NetworkControl::canEditForAll() const
{
    return m_source->status().permissions.modifySystem != Network::Permission::No;
}

bool NetworkControl::canHotspot() const
{
    if (m_source->status().permissions.wifiShareProtected == Network::Permission::No)
        return false;
    for (const auto &device : m_source->devices()) {
        if (device.canHotspot)
            return true;
    }
    return false;
}

QVariantMap NetworkControl::newSettings(const QString &ssid, int security) const
{
    ConnectionSettingsData settings;
    settings.name = ssid;
    settings.wifi.ssid = ssid.toUtf8();
    settings.security.security = static_cast<Network::Security>(security);
    // Like GNOME: the profile is the user's unless they may (and later choose to) share it
    settings.availableToAll = false;
    return settingsToMap(settings);
}

void NetworkControl::call(const QJSValue &callback, const Result &result, const QVariant &value)
{
    if (!callback.isCallable())
        return;
    QJSEngine *engine = qjsEngine(this);
    if (!engine)
        return;
    QJSValue object = engine->newObject();
    object.setProperty(QStringLiteral("ok"), result.error == Network::ErrorCode::None);
    object.setProperty(QStringLiteral("error"), int(result.error));
    object.setProperty(QStringLiteral("message"), result.message);
    QJSValue(callback).call({object, engine->toScriptValue(value)});
}

void NetworkControl::connectWithSettings(const QString &deviceId, const QVariantMap &settings, const QVariantList &secrets,
                                         const QJSValue &callback)
{
    m_source->connectWithSettings(deviceId, settingsFromMap(settings), secretsFromList(secrets),
                                  [self = QPointer(this), callback](const Result &result, const QString &uuid) {
                                      if (self)
                                          self->call(callback, result, uuid);
                                  });
}

void NetworkControl::settings(const QString &uuid, const QJSValue &callback)
{
    m_source->settings(uuid, [self = QPointer(this), callback](const Result &result, const ConnectionSettingsData &settings) {
        if (self)
            self->call(callback, result, settingsToMap(settings));
    });
}

void NetworkControl::updateSettings(const QString &uuid, const QVariantMap &settings, const QVariantList &secrets,
                                    const QJSValue &callback)
{
    m_source->updateSettings(uuid, settingsFromMap(settings), secretsFromList(secrets), [self = QPointer(this), callback](const Result &result) {
        if (self)
            self->call(callback, result);
    });
}

void NetworkControl::secrets(const QString &uuid, const QJSValue &callback)
{
    m_source->secrets(uuid, [self = QPointer(this), callback](const Result &result, const QList<SecretData> &secrets) {
        if (self)
            self->call(callback, result, secretsToList(secrets));
    });
}

void NetworkControl::qrCode(const QString &uuid, const QJSValue &callback)
{
    m_source->qrCode(uuid, [self = QPointer(this), callback](const Result &result, const QrCodeData &code) {
        if (self) {
            self->call(callback, result,
                       QVariantMap{{QStringLiteral("text"), code.text}, {QStringLiteral("size"), code.size}, {QStringLiteral("modules"), code.modules}});
        }
    });
}

void NetworkControl::startHotspot(const QString &deviceId, const QString &ssid, const QString &password, const QJSValue &callback)
{
    m_source->startHotspot(deviceId, ssid, password,
                           [self = QPointer(this), callback](const Result &result, const QString &uuid, const QString &password) {
                               if (self)
                                   self->call(callback, result, QVariantMap{{QStringLiteral("uuid"), uuid}, {QStringLiteral("password"), password}});
                           });
}

void NetworkControl::stopHotspot(const QString &deviceId, const QJSValue &callback)
{
    m_source->stopHotspot(deviceId, [self = QPointer(this), callback](const Result &result) {
        if (self)
            self->call(callback, result);
    });
}

bool NetworkControl::isValidAddress(const QString &text, bool ip6) const
{
    const QByteArray address = text.trimmed().toLatin1();
    unsigned char buffer[16];
    return !address.isEmpty() && inet_pton(ip6 ? AF_INET6 : AF_INET, address.constData(), buffer) == 1;
}

bool NetworkControl::isValidMac(const QString &text) const
{
    static const QRegularExpression mac(QStringLiteral("^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$"));
    return mac.match(text.trimmed()).hasMatch();
}

QString NetworkControl::hostName() const
{
    return QSysInfo::machineHostName();
}

QString NetworkControl::secretValue(const QVariantList &secrets, int key) const
{
    for (const auto &secret : secretsFromList(secrets)) {
        if (int(secret.key) == key)
            return secret.value;
    }
    return {};
}

} // namespace MaiaNetwork
