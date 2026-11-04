#include "NetworkSource.h"

#include "NetworkConnection.h"

#include <QCoreApplication>

namespace MaiaNetwork {

namespace {
NetworkSource *s_instance = nullptr;
}

bool Network::accepts(Validation validation, const QString &value)
{
    auto isHex = [](const QString &s) {
        for (QChar c : s) {
            if (!c.isDigit() && !(c.toLower() >= QLatin1Char('a') && c.toLower() <= QLatin1Char('f')))
                return false;
        }
        return true;
    };
    switch (validation) {
    case Validation::NotEmpty:
        return !value.isEmpty();
    case Validation::WpaPassword: {
        // Characters, not UTF-16 units
        const qsizetype n = value.toUcs4().size();
        return (n >= 8 && n <= 63) || (value.size() == 64 && isHex(value));
    }
    case Validation::WepKey: {
        const qsizetype n = value.size();
        bool ascii = true;
        for (QChar c : value)
            ascii = ascii && c.unicode() < 128;
        return ((n == 10 || n == 26) && isHex(value)) || ((n == 5 || n == 13) && ascii);
    }
    case Validation::WepPassphrase: {
        const qsizetype n = value.toUcs4().size();
        return n >= 1 && n <= 64;
    }
    }
    return false;
}

NetworkSource::NetworkSource(QObject *parent)
    : QObject(parent)
{
}

NetworkSource *NetworkSource::instance()
{
    if (!s_instance) {
        // Lives as long as the application; its thread ends before the application object is gone
        s_instance = new NetworkConnection(NetworkConnection::defaultSocketPath(), QCoreApplication::instance());
    }
    return s_instance;
}

void NetworkSource::setInstance(NetworkSource *source)
{
    s_instance = source;
}

NetworkSource *NetworkSource::existingInstance()
{
    return s_instance;
}

Result NetworkSource::unavailable()
{
    return Result{Network::ErrorCode::Unavailable, QStringLiteral("the network service is not running")};
}

const DeviceData *NetworkSource::device(const QString &id) const
{
    auto it = m_devices.constFind(id);
    return it == m_devices.cend() ? nullptr : &*it;
}

const NetworkData *NetworkSource::network(const QString &id) const
{
    auto it = m_networks.constFind(id);
    return it == m_networks.cend() ? nullptr : &*it;
}

const ConnectionData *NetworkSource::connection(const QString &uuid) const
{
    auto it = m_connections.constFind(uuid);
    return it == m_connections.cend() ? nullptr : &*it;
}

void NetworkSource::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    if (!connected) {
        // Without the service nothing is known: the interface shows "unavailable", not stale networks
        applySnapshot(StatusData{}, {}, {}, {});
    }
    Q_EMIT connectedChanged();
}

void NetworkSource::applySnapshot(const StatusData &status, const QList<DeviceData> &devices,
                                  const QList<NetworkData> &networks, const QList<ConnectionData> &connections)
{
    m_status = status;
    m_devices.clear();
    for (const auto &device : devices)
        m_devices.insert(device.id, device);
    m_networks.clear();
    for (const auto &network : networks)
        m_networks.insert(network.id, network);
    m_connections.clear();
    for (const auto &connection : connections)
        m_connections.insert(connection.uuid, connection);
    Q_EMIT reset();
    Q_EMIT statusChanged();
}

void NetworkSource::applyStatus(const StatusData &status)
{
    if (m_status == status)
        return;
    m_status = status;
    Q_EMIT statusChanged();
}

void NetworkSource::upsertDevice(const DeviceData &device)
{
    auto it = m_devices.find(device.id);
    if (it != m_devices.end() && *it == device)
        return;
    m_devices.insert(device.id, device);
    Q_EMIT deviceChanged(device.id);
}

void NetworkSource::removeDevice(const QString &id)
{
    if (m_devices.remove(id))
        Q_EMIT deviceRemoved(id);
}

void NetworkSource::upsertNetwork(const NetworkData &network)
{
    auto it = m_networks.find(network.id);
    if (it != m_networks.end() && *it == network)
        return;
    m_networks.insert(network.id, network);
    Q_EMIT networkChanged(network.id);
}

void NetworkSource::removeNetwork(const QString &id)
{
    if (m_networks.remove(id))
        Q_EMIT networkRemoved(id);
}

void NetworkSource::upsertConnection(const ConnectionData &connection)
{
    auto it = m_connections.find(connection.uuid);
    if (it != m_connections.end() && *it == connection)
        return;
    m_connections.insert(connection.uuid, connection);
    Q_EMIT connectionChanged(connection.uuid);
}

void NetworkSource::removeConnection(const QString &uuid)
{
    if (m_connections.remove(uuid))
        Q_EMIT connectionRemoved(uuid);
}

void NetworkSource::applyActivationFailed(const QString &deviceId, const QString &uuid, const QString &name,
                                          Network::StateReason reason)
{
    Q_EMIT activationFailed(deviceId, uuid, name, reason);
}

void NetworkSource::applyConnected(const QString &uuid)
{
    Q_EMIT connectedTo(uuid);
}

void NetworkSource::applySecretRequest(const SecretRequestData &request)
{
    Q_EMIT secretRequested(request);
}

void NetworkSource::applySecretCancel(const QString &id)
{
    Q_EMIT secretCancelled(id);
}

} // namespace MaiaNetwork
