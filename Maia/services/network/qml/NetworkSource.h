#pragma once

// The network state of a process, in the GUI thread, and the commands it can send.
//
// NetworkConnection fills it from the service (the only source in production); tests fill it
// directly (tests/tst_networkmodels.cpp). The QML types (WifiStatus, the models, SecretPrompt)
// only read it and call its commands, so they never see Cap'n Proto or threads.
//
// Every command takes an optional callback, called in the GUI thread with the service's result
// (also when the service is not there: Network.ErrorCode.Unavailable).

#include "NetworkTypes.h"

#include <QHash>
#include <QObject>
#include <functional>

namespace MaiaNetwork {

class NetworkSource : public QObject
{
    Q_OBJECT

public:
    using Callback = std::function<void(const Result &)>;
    template<typename... Values>
    using ValueCallback = std::function<void(const Result &, const Values &...)>;

    explicit NetworkSource(QObject *parent = nullptr);

    // The process's source (the connection to the service), created on first use; a test sets its own
    static NetworkSource *instance();
    static void setInstance(NetworkSource *source);
    // The process's source if there is one, without creating it
    static NetworkSource *existingInstance();

    bool isConnected() const { return m_connected; }
    const StatusData &status() const { return m_status; }
    const QHash<QString, DeviceData> &devices() const { return m_devices; }
    const QHash<QString, NetworkData> &networks() const { return m_networks; }
    const QHash<QString, ConnectionData> &connections() const { return m_connections; }
    const DeviceData *device(const QString &id) const;
    const NetworkData *network(const QString &id) const;
    const ConnectionData *connection(const QString &uuid) const;

    // --- Filling (GUI thread) ---

    void setConnected(bool connected);
    void applySnapshot(const StatusData &status, const QList<DeviceData> &devices, const QList<NetworkData> &networks,
                       const QList<ConnectionData> &connections);
    void applyStatus(const StatusData &status);
    void upsertDevice(const DeviceData &device);
    void removeDevice(const QString &id);
    void upsertNetwork(const NetworkData &network);
    void removeNetwork(const QString &id);
    void upsertConnection(const ConnectionData &connection);
    void removeConnection(const QString &uuid);
    void applyActivationFailed(const QString &deviceId, const QString &uuid, const QString &name, Network::StateReason reason);
    void applyConnected(const QString &uuid);
    void applySecretRequest(const SecretRequestData &request);
    void applySecretCancel(const QString &id);

    // --- Commands ---

    virtual void setWirelessEnabled(bool enabled, Callback done = {}) = 0;
    virtual void requestScan(const QString &deviceId, Callback done = {}) = 0;
    virtual void connectNetwork(const QString &networkId, Callback done = {}) = 0;
    virtual void activate(const QString &uuid, const QString &deviceId, Callback done = {}) = 0;
    virtual void disconnectDevice(const QString &deviceId, Callback done = {}) = 0;
    virtual void forget(const QString &uuid, Callback done = {}) = 0;
    virtual void checkConnectivity(Callback done = {}) = 0;
    // A hidden or Enterprise network from settings; done gets the new profile's UUID
    virtual void connectWithSettings(const QString &deviceId, const ConnectionSettingsData &settings,
                                     const QList<SecretData> &secrets, ValueCallback<QString> done = {}) = 0;
    virtual void settings(const QString &uuid, ValueCallback<ConnectionSettingsData> done) = 0;
    // secrets: only those the user changed
    virtual void updateSettings(const QString &uuid, const ConnectionSettingsData &settings, const QList<SecretData> &secrets,
                                Callback done = {}) = 0;
    virtual void secrets(const QString &uuid, ValueCallback<QList<SecretData>> done) = 0;
    virtual void qrCode(const QString &uuid, ValueCallback<QrCodeData> done) = 0;
    // password "" = keep the hotspot's or make one; done gets the profile UUID and the password
    virtual void startHotspot(const QString &deviceId, const QString &ssid, const QString &password,
                              ValueCallback<QString, QString> done = {}) = 0;
    virtual void stopHotspot(const QString &deviceId, Callback done = {}) = 0;

    // The shell asks the user for passwords while registered (one per session)
    virtual void setPrompterRegistered(bool registered) = 0;
    // The answer to a SecretRequest: cancelled, or the secrets the user typed
    virtual void answerSecrets(const QString &requestId, bool cancelled, const QList<SecretData> &secrets) = 0;

Q_SIGNALS:
    void connectedChanged();
    // The whole state was replaced (a new connection to the service)
    void reset();
    void statusChanged();
    void deviceChanged(const QString &id);
    void deviceRemoved(const QString &id);
    void networkChanged(const QString &id);
    void networkRemoved(const QString &id);
    void connectionChanged(const QString &uuid);
    void connectionRemoved(const QString &uuid);
    void activationFailed(const QString &deviceId, const QString &uuid, const QString &name, MaiaNetwork::Network::StateReason reason);
    void connectedTo(const QString &uuid);
    void secretRequested(const MaiaNetwork::SecretRequestData &request);
    void secretCancelled(const QString &id);

protected:
    // For commands while the service is not there
    static Result unavailable();

private:
    bool m_connected = false;
    StatusData m_status;
    QHash<QString, DeviceData> m_devices;
    QHash<QString, NetworkData> m_networks;
    QHash<QString, ConnectionData> m_connections;
};

} // namespace MaiaNetwork
