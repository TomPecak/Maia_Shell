#pragma once

// What the details editor, the hidden network dialog and the hotspot need (a singleton):
//
//   import Maia.Network
//   NetworkControl.settings(uuid, (result, settings) => { if (result.ok) editor.load(settings) })
//   NetworkControl.updateSettings(uuid, edited, [], result => { if (!result.ok) showError(result) })
//   NetworkControl.qrCode(uuid, (result, code) => { qr.modules = code.modules; qr.moduleCount = code.size })
//   NetworkControl.startHotspot("", "", "", (result, hotspot) => passwordLabel.text = hotspot.password)
//
// Settings and secrets are JavaScript objects (SettingsMap.h). Every call is asynchronous: the
// callback gets { ok, error, message } (error: Network.ErrorCode) and the call's value.

#include "NetworkSource.h"

#include <QJSValue>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

class NetworkControl : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Profiles can be made available to all users (else "Available to all users" is disabled)
    Q_PROPERTY(bool canEditForAll READ canEditForAll NOTIFY changed)
    // An adapter can be an access point and polkit lets this user share
    Q_PROPERTY(bool canHotspot READ canHotspot NOTIFY changed)

public:
    explicit NetworkControl(QObject *parent = nullptr);

    bool canEditForAll() const;
    bool canHotspot() const;

    // The settings of a new profile (a hidden network): automatic addresses, connects by itself
    Q_INVOKABLE QVariantMap newSettings(const QString &ssid = {}, int security = 0) const;

    // A hidden (#14) or Enterprise (#22) network; callback(result, uuid). deviceId "" = the first adapter
    Q_INVOKABLE void connectWithSettings(const QString &deviceId, const QVariantMap &settings, const QVariantList &secrets,
                                         const QJSValue &callback = {});
    // callback(result, settings)
    Q_INVOKABLE void settings(const QString &uuid, const QJSValue &callback);
    // secrets: only those the user changed; callback(result)
    Q_INVOKABLE void updateSettings(const QString &uuid, const QVariantMap &settings, const QVariantList &secrets = {},
                                    const QJSValue &callback = {});
    // The saved secrets ("show password"); may ask polkit; callback(result, secrets)
    Q_INVOKABLE void secrets(const QString &uuid, const QJSValue &callback);
    // callback(result, { text, size, modules }) for a QrCodeView
    Q_INVOKABLE void qrCode(const QString &uuid, const QJSValue &callback);
    // ssid "" = the host name, password "" = the hotspot's own or a new one;
    // callback(result, { uuid, password })
    Q_INVOKABLE void startHotspot(const QString &deviceId, const QString &ssid = {}, const QString &password = {},
                                  const QJSValue &callback = {});
    Q_INVOKABLE void stopHotspot(const QString &deviceId, const QJSValue &callback = {});

    // Checks for the editor's fields
    Q_INVOKABLE bool isValidAddress(const QString &text, bool ip6) const;
    Q_INVOKABLE bool isValidMac(const QString &text) const;
    // The value of a key in a secrets list, "" when it is not there
    Q_INVOKABLE QString secretValue(const QVariantList &secrets, int key) const;

Q_SIGNALS:
    void changed();

private:
    // callback(result, value) with the value converted for JavaScript
    void call(const QJSValue &callback, const Result &result, const QVariant &value = {});

    NetworkSource *m_source;
};

} // namespace MaiaNetwork
