#pragma once

// The state of Wi-Fi at a glance, for a quick settings tile, a status icon, a toggle:
//
//   import Maia.Network
//   WifiStatus { id: wifi }
//   Switch { checked: wifi.enabled; enabled: wifi.canToggle; onToggled: wifi.setEnabled(checked) }
//   Label { text: wifi.connected ? wifi.networkName : qsTr("Not connected") }
//
// Any number of instances; they share the process's connection to the network service.

#include "NetworkSource.h"

#include <QJSValue>
#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

class WifiStatus : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // The network service answers and NetworkManager runs: otherwise everything below is empty
    Q_PROPERTY(bool available READ available NOTIFY changed)
    // There is a Wi-Fi adapter
    Q_PROPERTY(bool hasDevice READ hasDevice NOTIFY changed)
    Q_PROPERTY(bool enabled READ enabled NOTIFY changed)
    // false: a hardware switch blocks Wi-Fi
    Q_PROPERTY(bool hardwareEnabled READ hardwareEnabled NOTIFY changed)
    // Wi-Fi can be switched here (polkit allows it, the hardware switch does not block it)
    Q_PROPERTY(bool canToggle READ canToggle NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    // Connecting or waiting for a password
    Q_PROPERTY(bool connecting READ connecting NOTIFY changed)
    Q_PROPERTY(bool scanning READ scanning NOTIFY changed)
    // The device shares a connection (a hotspot)
    Q_PROPERTY(bool hotspot READ hotspot NOTIFY changed)
    // The connected (or connecting) network
    Q_PROPERTY(QString networkName READ networkName NOTIFY changed)
    Q_PROPERTY(QString networkId READ networkId NOTIFY changed)
    Q_PROPERTY(int strength READ strength NOTIFY changed)
    // 0 none, 1 weak, 2 ok, 3 good, 4 excellent (GNOME's icon steps)
    Q_PROPERTY(int signalLevel READ signalLevel NOTIFY changed)
    Q_PROPERTY(MaiaNetwork::Network::Security security READ security NOTIFY changed)
    Q_PROPERTY(MaiaNetwork::Network::Connectivity connectivity READ connectivity NOTIFY changed)
    // A captive portal waits for a sign-in (open portalUri in a browser)
    Q_PROPERTY(bool portal READ portal NOTIFY changed)
    Q_PROPERTY(QString portalUri READ portalUri NOTIFY changed)
    // The internet is reached through Wi-Fi (not ethernet)
    Q_PROPERTY(bool primary READ primary NOTIFY changed)

public:
    explicit WifiStatus(QObject *parent = nullptr);

    bool available() const;
    bool hasDevice() const;
    bool enabled() const;
    bool hardwareEnabled() const;
    bool canToggle() const;
    bool connected() const;
    bool connecting() const;
    bool scanning() const;
    bool hotspot() const;
    QString networkName() const;
    QString networkId() const;
    int strength() const;
    int signalLevel() const;
    Network::Security security() const;
    Network::Connectivity connectivity() const;
    bool portal() const;
    QString portalUri() const;
    bool primary() const;

    // Each takes an optional callback, called with { ok, error, message }
    Q_INVOKABLE void setEnabled(bool enabled, const QJSValue &callback = {});
    Q_INVOKABLE void toggle(const QJSValue &callback = {});
    // Scans on every Wi-Fi device (NetworkManager limits how often)
    Q_INVOKABLE void scan(const QJSValue &callback = {});
    // After signing in at a captive portal
    Q_INVOKABLE void checkConnectivity(const QJSValue &callback = {});
    // Opens the captive portal's address in the default browser
    Q_INVOKABLE void openPortal();

Q_SIGNALS:
    void changed();
    // A connection failed (not when the user cancelled the password dialog)
    void activationFailed(const QString &name, MaiaNetwork::Network::StateReason reason);
    void connectedTo(const QString &name);

private:
    // The Wi-Fi device that matters: the one connected or connecting, else the first
    const DeviceData *mainDevice() const;
    const NetworkData *activeNetwork() const;

    NetworkSource *m_source;
};

} // namespace MaiaNetwork
