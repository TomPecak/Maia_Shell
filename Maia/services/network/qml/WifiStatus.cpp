#include "WifiStatus.h"

#include "QmlHelpers.h"

#include <QDesktopServices>
#include <QUrl>

namespace MaiaNetwork {

WifiStatus::WifiStatus(QObject *parent)
    : QObject(parent)
    , m_source(NetworkSource::instance())
{
    auto changed = [this] { Q_EMIT this->changed(); };
    connect(m_source, &NetworkSource::connectedChanged, this, changed);
    connect(m_source, &NetworkSource::reset, this, changed);
    connect(m_source, &NetworkSource::statusChanged, this, changed);
    connect(m_source, &NetworkSource::deviceChanged, this, changed);
    connect(m_source, &NetworkSource::deviceRemoved, this, changed);
    connect(m_source, &NetworkSource::networkChanged, this, [this](const QString &id) {
        const auto *device = mainDevice();
        if (device && device->activeNetworkId == id)
            Q_EMIT this->changed();
    });
    connect(m_source, &NetworkSource::activationFailed, this,
            [this](const QString &, const QString &, const QString &name, Network::StateReason reason) {
                Q_EMIT activationFailed(name, reason);
            });
    connect(m_source, &NetworkSource::connectedTo, this, [this](const QString &uuid) {
        const auto *connection = m_source->connection(uuid);
        Q_EMIT connectedTo(connection ? connection->name : QString());
    });
}

const DeviceData *WifiStatus::mainDevice() const
{
    const DeviceData *first = nullptr;
    for (const auto &device : m_source->devices()) {
        if (!device.activeConnectionUuid.isEmpty())
            return &device;
        if (!first || device.id < first->id)
            first = &device;
    }
    return first;
}

const NetworkData *WifiStatus::activeNetwork() const
{
    const auto *device = mainDevice();
    return device ? m_source->network(device->activeNetworkId) : nullptr;
}

bool WifiStatus::available() const
{
    return m_source->isConnected() && m_source->status().running;
}

bool WifiStatus::hasDevice() const
{
    return !m_source->devices().isEmpty();
}

bool WifiStatus::enabled() const
{
    return m_source->status().wirelessEnabled;
}

bool WifiStatus::hardwareEnabled() const
{
    return m_source->status().wirelessHardwareEnabled;
}

bool WifiStatus::canToggle() const
{
    return available() && hardwareEnabled() && m_source->status().permissions.enableDisableWifi != Network::Permission::No;
}

bool WifiStatus::connected() const
{
    const auto *device = mainDevice();
    return device && device->state == Network::DeviceState::Connected && !device->hotspot;
}

bool WifiStatus::connecting() const
{
    const auto *device = mainDevice();
    return device && (device->state == Network::DeviceState::Connecting || device->state == Network::DeviceState::NeedAuth);
}

bool WifiStatus::scanning() const
{
    for (const auto &device : m_source->devices()) {
        if (device.scanning)
            return true;
    }
    return false;
}

bool WifiStatus::hotspot() const
{
    const auto *device = mainDevice();
    return device && device->hotspot;
}

QString WifiStatus::networkName() const
{
    if (const auto *network = activeNetwork())
        return network->name;
    // A hidden network or a hotspot: the profile's name
    const auto *device = mainDevice();
    const auto *connection = device ? m_source->connection(device->activeConnectionUuid) : nullptr;
    return connection ? connection->name : QString();
}

QString WifiStatus::networkId() const
{
    const auto *device = mainDevice();
    return device ? device->activeNetworkId : QString();
}

int WifiStatus::strength() const
{
    const auto *network = activeNetwork();
    return network ? network->strength : 0;
}

int WifiStatus::signalLevel() const
{
    return Network::signalLevel(strength());
}

Network::Security WifiStatus::security() const
{
    const auto *network = activeNetwork();
    return network ? network->security : Network::Security::None;
}

Network::Connectivity WifiStatus::connectivity() const
{
    return m_source->status().connectivity;
}

bool WifiStatus::portal() const
{
    return connectivity() == Network::Connectivity::Portal;
}

QString WifiStatus::portalUri() const
{
    return m_source->status().connectivityCheckUri;
}

bool WifiStatus::primary() const
{
    return m_source->status().primaryType == Network::ConnectionType::Wifi;
}

void WifiStatus::setEnabled(bool enabled, const QJSValue &callback)
{
    m_source->setWirelessEnabled(enabled, jsCallback(this, callback));
}

void WifiStatus::toggle(const QJSValue &callback)
{
    setEnabled(!enabled(), callback);
}

void WifiStatus::scan(const QJSValue &callback)
{
    m_source->requestScan(QString(), jsCallback(this, callback));
}

void WifiStatus::checkConnectivity(const QJSValue &callback)
{
    m_source->checkConnectivity(jsCallback(this, callback));
}

void WifiStatus::openPortal()
{
    const QString uri = portalUri();
    if (!uri.isEmpty())
        QDesktopServices::openUrl(QUrl(uri));
}

} // namespace MaiaNetwork
