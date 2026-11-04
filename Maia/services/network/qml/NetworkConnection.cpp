#include "NetworkConnection.h"

#include "network.capnp.h"

#include <capnp/rpc-twoparty.h>
#include <kj/async-io.h>
#include <kj/async-unix.h>

#include <QDebug>
#include <QDir>
#include <QFileInfo>

#include <map>
#include <memory>
#include <string>
#include <tuple>

#include <sys/eventfd.h>
#include <unistd.h>

namespace C = MaiaNetwork::Contract;

namespace MaiaNetwork {

namespace {

// The enumerations of NetworkTypes.h are those of the contract, in the same order
static_assert(int(C::Security::WPA3_ENTERPRISE) == int(Network::Security::Wpa3Enterprise));
static_assert(int(C::DeviceState::FAILED) == int(Network::DeviceState::Failed));
static_assert(int(C::StateReason::CARRIER_LOST) == int(Network::StateReason::CarrierLost));
static_assert(int(C::Connectivity::FULL) == int(Network::Connectivity::Full));
static_assert(int(C::SecretKey::EAP_IDENTITY) == int(Network::SecretKey::EapIdentity));
static_assert(int(C::Validation::WEP_PASSPHRASE) == int(Network::Validation::WepPassphrase));
static_assert(int(C::ErrorCode::FAILED) == int(Network::ErrorCode::Failed));
static_assert(int(C::Metered::NO) == int(Network::Metered::No));
static_assert(int(C::ConnectionType::OTHER) == int(Network::ConnectionType::Other));
static_assert(int(C::Permission::YES) == int(Network::Permission::Yes));
static_assert(C::BAND24_G_HZ == Network::Band24GHz && C::BAND5_G_HZ == Network::Band5GHz && C::BAND6_G_HZ == Network::Band6GHz);

template<typename To, typename From>
To as(From value)
{
    return static_cast<To>(static_cast<int>(value));
}

QString text(capnp::Text::Reader text)
{
    return QString::fromUtf8(text.begin(), qsizetype(text.size()));
}

QByteArray bytes(capnp::Data::Reader data)
{
    return QByteArray(reinterpret_cast<const char *>(data.begin()), qsizetype(data.size()));
}

QStringList texts(capnp::List<capnp::Text>::Reader list)
{
    QStringList out;
    for (auto item : list)
        out.append(text(item));
    return out;
}

IpInfo toIp(C::IpInfo::Reader r)
{
    IpInfo info;
    for (auto a : r.getAddresses())
        info.addresses.append(text(a.getAddress()) + QLatin1Char('/') + QString::number(a.getPrefix()));
    info.gateway = text(r.getGateway());
    info.dns = texts(r.getDns());
    return info;
}

StatusData toStatus(C::Status::Reader r)
{
    StatusData s;
    s.running = r.getRunning();
    s.networkingEnabled = r.getNetworkingEnabled();
    s.wirelessEnabled = r.getWirelessEnabled();
    s.wirelessHardwareEnabled = r.getWirelessHardwareEnabled();
    s.connectivity = as<Network::Connectivity>(r.getConnectivity());
    s.connectivityCheckUri = text(r.getConnectivityCheckUri());
    const auto p = r.getPrimary();
    s.primaryType = as<Network::ConnectionType>(p.getType());
    s.primaryName = text(p.getName());
    s.primaryUuid = text(p.getUuid());
    s.primaryDeviceId = text(p.getDeviceId());
    s.primaryActivating = p.getActivating();
    const auto m = r.getPermissions();
    s.permissions.enableDisableWifi = as<Network::Permission>(m.getEnableDisableWifi());
    s.permissions.networkControl = as<Network::Permission>(m.getNetworkControl());
    s.permissions.modifyOwn = as<Network::Permission>(m.getModifyOwn());
    s.permissions.modifySystem = as<Network::Permission>(m.getModifySystem());
    s.permissions.wifiShareOpen = as<Network::Permission>(m.getWifiShareOpen());
    s.permissions.wifiShareProtected = as<Network::Permission>(m.getWifiShareProtected());
    return s;
}

DeviceData toDevice(C::WifiDevice::Reader r)
{
    DeviceData d;
    d.id = text(r.getId());
    d.name = text(r.getName());
    d.hwAddress = text(r.getHwAddress());
    d.permHwAddress = text(r.getPermHwAddress());
    d.state = as<Network::DeviceState>(r.getState());
    d.stateReason = as<Network::StateReason>(r.getStateReason());
    d.activeNetworkId = text(r.getActiveNetworkId());
    d.activeConnectionUuid = text(r.getActiveConnectionUuid());
    d.hotspot = r.getHotspot();
    d.bitrate = r.getBitrate();
    d.bands = r.getBands();
    d.canHotspot = r.getCanHotspot();
    d.scanning = r.getScanning();
    d.lastScan = r.getLastScan();
    d.ip4 = toIp(r.getIp4());
    d.ip6 = toIp(r.getIp6());
    return d;
}

NetworkData toNetwork(C::WifiNetwork::Reader r)
{
    NetworkData n;
    n.id = text(r.getId());
    n.deviceId = text(r.getDeviceId());
    n.ssid = bytes(r.getSsid());
    n.name = text(r.getName());
    n.security = as<Network::Security>(r.getSecurity());
    n.strength = r.getStrength();
    n.frequency = r.getFrequency();
    n.bands = r.getBands();
    n.connectionUuids = texts(r.getConnectionUuids());
    n.active = r.getActive();
    for (auto ap : r.getAccessPoints()) {
        n.accessPoints.append(AccessPointData{text(ap.getBssid()), ap.getStrength(), ap.getFrequency(), ap.getMaxBitrate(),
                                              ap.getLastSeen()});
    }
    return n;
}

ConnectionData toConnection(C::SavedConnection::Reader r)
{
    ConnectionData c;
    c.uuid = text(r.getUuid());
    c.name = text(r.getName());
    c.ssid = bytes(r.getSsid());
    c.ssidText = text(r.getSsidText());
    c.security = as<Network::Security>(r.getSecurity());
    c.hidden = r.getHidden();
    c.hotspot = r.getHotspot();
    c.autoconnect = r.getAutoconnect();
    c.metered = as<Network::Metered>(r.getMetered());
    c.availableToAll = r.getAvailableToAll();
    c.lastUsed = r.getLastUsed();
    c.activeDeviceId = text(r.getActiveDeviceId());
    c.qrSupported = r.getQrSupported();
    return c;
}

SecretRequestData toRequest(C::SecretRequest::Reader r)
{
    SecretRequestData request;
    request.id = text(r.getId());
    request.connectionUuid = text(r.getConnectionUuid());
    request.name = text(r.getName());
    request.deviceId = text(r.getDeviceId());
    request.security = as<Network::Security>(r.getSecurity());
    request.retry = r.getRetry();
    request.wpsPushButton = r.getWpsPushButton();
    for (auto f : r.getFields()) {
        request.fields.append(SecretFieldData{as<Network::SecretKey>(f.getKey()), text(f.getValue()), f.getHidden(),
                                              as<Network::Validation>(f.getValidation())});
    }
    return request;
}

Result toResult(C::Result::Reader r)
{
    return Result{as<Network::ErrorCode>(r.getError()), text(r.getMessage())};
}

static_assert(int(C::IpMethod::DISABLED) == int(Network::IpMethod::Disabled));
static_assert(int(C::ClonedMac::ADDRESS) == int(Network::ClonedMac::Address));
static_assert(int(C::EapMethod::LEAP) == int(Network::EapMethod::Leap));
static_assert(int(C::InnerAuth::MD5) == int(Network::InnerAuth::Md5));

std::string utf8(const QString &text)
{
    return text.toStdString();
}

capnp::Data::Reader data(const QByteArray &bytes)
{
    return capnp::Data::Reader(reinterpret_cast<const kj::byte *>(bytes.constData()), size_t(bytes.size()));
}

void setTexts(capnp::List<capnp::Text>::Builder list, const QStringList &texts)
{
    for (int i = 0; i < texts.size(); ++i)
        list.set(i, utf8(texts[i]).c_str());
}

IpSettingsData toIpSettings(C::IpSettings::Reader r)
{
    IpSettingsData ip;
    ip.method = as<Network::IpMethod>(r.getMethod());
    for (auto a : r.getAddresses())
        ip.addresses.append(IpAddressData{text(a.getAddress()), a.getPrefix()});
    ip.gateway = text(r.getGateway());
    ip.autoDns = r.getAutoDns();
    ip.dns = texts(r.getDns());
    ip.dnsSearch = texts(r.getDnsSearch());
    ip.autoRoutes = r.getAutoRoutes();
    for (auto route : r.getRoutes())
        ip.routes.append(RouteData{text(route.getDestination()), route.getPrefix(), text(route.getGateway()), route.getMetric()});
    ip.neverDefault = r.getNeverDefault();
    return ip;
}

void writeIpSettings(C::IpSettings::Builder b, const IpSettingsData &ip)
{
    b.setMethod(as<C::IpMethod>(ip.method));
    auto addresses = b.initAddresses(unsigned(ip.addresses.size()));
    for (int i = 0; i < ip.addresses.size(); ++i) {
        addresses[i].setAddress(utf8(ip.addresses[i].address).c_str());
        addresses[i].setPrefix(uint8_t(ip.addresses[i].prefix));
    }
    b.setGateway(utf8(ip.gateway).c_str());
    b.setAutoDns(ip.autoDns);
    setTexts(b.initDns(unsigned(ip.dns.size())), ip.dns);
    setTexts(b.initDnsSearch(unsigned(ip.dnsSearch.size())), ip.dnsSearch);
    b.setAutoRoutes(ip.autoRoutes);
    auto routes = b.initRoutes(unsigned(ip.routes.size()));
    for (int i = 0; i < ip.routes.size(); ++i) {
        const auto &route = ip.routes[i];
        routes[i].setDestination(utf8(route.destination).c_str());
        routes[i].setPrefix(uint8_t(route.prefix));
        routes[i].setGateway(utf8(route.gateway).c_str());
        routes[i].setMetric(route.metric);
    }
    b.setNeverDefault(ip.neverDefault);
}

ConnectionSettingsData toSettings(C::ConnectionSettings::Reader r)
{
    ConnectionSettingsData settings;
    settings.name = text(r.getName());
    settings.autoconnect = r.getAutoconnect();
    settings.metered = as<Network::Metered>(r.getMetered());
    settings.availableToAll = r.getAvailableToAll();
    auto w = r.getWifi();
    settings.wifi = WifiSettingsData{bytes(w.getSsid()), w.getHidden(), text(w.getBssid()), text(w.getMacAddress()),
                                     as<Network::ClonedMac>(w.getClonedMac()), text(w.getClonedMacAddress())};
    auto sec = r.getSecurity();
    settings.security.security = as<Network::Security>(sec.getSecurity());
    settings.security.wepKeyIndex = sec.getWepKeyIndex();
    settings.security.wepPassphrase = sec.getWepPassphrase();
    settings.security.leapUsername = text(sec.getLeapUsername());
    auto e = sec.getEap();
    settings.security.eap = EapSettingsData{as<Network::EapMethod>(e.getMethod()),
                                            text(e.getIdentity()),
                                            text(e.getAnonymousIdentity()),
                                            text(e.getCaCertificate()),
                                            e.getNoCaCertificate(),
                                            text(e.getDomain()),
                                            text(e.getClientCertificate()),
                                            text(e.getPrivateKey()),
                                            as<Network::InnerAuth>(e.getInnerAuth()),
                                            text(e.getPacFile()),
                                            e.getPeapVersion()};
    settings.ip4 = toIpSettings(r.getIp4());
    settings.ip6 = toIpSettings(r.getIp6());
    return settings;
}

void writeSettings(C::ConnectionSettings::Builder b, const ConnectionSettingsData &settings)
{
    b.setName(utf8(settings.name).c_str());
    b.setAutoconnect(settings.autoconnect);
    b.setMetered(as<C::Metered>(settings.metered));
    b.setAvailableToAll(settings.availableToAll);
    auto w = b.initWifi();
    w.setSsid(data(settings.wifi.ssid));
    w.setHidden(settings.wifi.hidden);
    w.setBssid(utf8(settings.wifi.bssid).c_str());
    w.setMacAddress(utf8(settings.wifi.macAddress).c_str());
    w.setClonedMac(as<C::ClonedMac>(settings.wifi.clonedMac));
    w.setClonedMacAddress(utf8(settings.wifi.clonedMacAddress).c_str());
    auto sec = b.initSecurity();
    sec.setSecurity(as<C::Security>(settings.security.security));
    sec.setWepKeyIndex(uint8_t(settings.security.wepKeyIndex));
    sec.setWepPassphrase(settings.security.wepPassphrase);
    sec.setLeapUsername(utf8(settings.security.leapUsername).c_str());
    const auto &eap = settings.security.eap;
    auto e = sec.initEap();
    e.setMethod(as<C::EapMethod>(eap.method));
    e.setIdentity(utf8(eap.identity).c_str());
    e.setAnonymousIdentity(utf8(eap.anonymousIdentity).c_str());
    e.setCaCertificate(utf8(eap.caCertificate).c_str());
    e.setNoCaCertificate(eap.noCaCertificate);
    e.setDomain(utf8(eap.domain).c_str());
    e.setClientCertificate(utf8(eap.clientCertificate).c_str());
    e.setPrivateKey(utf8(eap.privateKey).c_str());
    e.setInnerAuth(as<C::InnerAuth>(eap.innerAuth));
    e.setPacFile(utf8(eap.pacFile).c_str());
    e.setPeapVersion(int8_t(eap.peapVersion));
    writeIpSettings(b.initIp4(), settings.ip4);
    writeIpSettings(b.initIp6(), settings.ip6);
}

QList<SecretData> toSecrets(capnp::List<C::Secret>::Reader list)
{
    QList<SecretData> secrets;
    for (auto secret : list)
        secrets.append(SecretData{as<Network::SecretKey>(secret.getKey()), text(secret.getValue())});
    return secrets;
}

void writeSecrets(capnp::List<C::Secret>::Builder list, const QList<SecretData> &secrets)
{
    for (int i = 0; i < secrets.size(); ++i) {
        list[i].setKey(as<C::SecretKey>(secrets[i].key));
        list[i].setValue(utf8(secrets[i].value).c_str());
    }
}

class LogErrors final : public kj::TaskSet::ErrorHandler
{
public:
    void taskFailed(kj::Exception &&exception) override
    {
        qWarning() << "[Maia.Network]" << exception.getDescription().cStr();
    }
};

// What the user answered a password request with, waiting in the KJ thread
struct Reply {
    bool cancelled = true;
    std::vector<std::pair<C::SecretKey, std::string>> secrets;
};

using PendingAsks = std::map<std::string, kj::Own<kj::PromiseFulfiller<Reply>>>;

} // namespace

// What exists only in the KJ thread, for one connection
struct KjContext {
    C::NetworkService::Client service;
    C::NetworkControl::Client control;
    kj::TaskSet &tasks;
    std::shared_ptr<PendingAsks> pending;
    kj::Maybe<C::Subscription::Client> registration;
};

// Called by the service (in the KJ thread); hands the changes to the GUI thread in their order
class Listener final : public C::NetworkListener::Server
{
public:
    explicit Listener(NetworkConnection *connection)
        : m_c(connection)
    {
    }

protected:
    kj::Promise<void> snapshot(SnapshotContext context) override
    {
        const auto s = context.getParams().getSnapshot();
        StatusData status = toStatus(s.getStatus());
        QList<DeviceData> devices;
        for (auto d : s.getDevices())
            devices.append(toDevice(d));
        QList<NetworkData> networks;
        for (auto n : s.getNetworks())
            networks.append(toNetwork(n));
        QList<ConnectionData> connections;
        for (auto c : s.getConnections())
            connections.append(toConnection(c));
        m_c->toGui([c = m_c, status, devices, networks, connections] {
            c->applySnapshot(status, devices, networks, connections);
            c->setConnected(true);
        });
        return kj::READY_NOW;
    }

    kj::Promise<void> statusChanged(StatusChangedContext context) override
    {
        auto status = toStatus(context.getParams().getStatus());
        m_c->toGui([c = m_c, status] { c->applyStatus(status); });
        return kj::READY_NOW;
    }

    kj::Promise<void> deviceChanged(DeviceChangedContext context) override
    {
        auto device = toDevice(context.getParams().getDevice());
        m_c->toGui([c = m_c, device] { c->upsertDevice(device); });
        return kj::READY_NOW;
    }

    kj::Promise<void> deviceRemoved(DeviceRemovedContext context) override
    {
        auto id = text(context.getParams().getId());
        m_c->toGui([c = m_c, id] { c->removeDevice(id); });
        return kj::READY_NOW;
    }

    kj::Promise<void> networkChanged(NetworkChangedContext context) override
    {
        auto network = toNetwork(context.getParams().getNetwork());
        m_c->toGui([c = m_c, network] { c->upsertNetwork(network); });
        return kj::READY_NOW;
    }

    kj::Promise<void> networkRemoved(NetworkRemovedContext context) override
    {
        auto id = text(context.getParams().getId());
        m_c->toGui([c = m_c, id] { c->removeNetwork(id); });
        return kj::READY_NOW;
    }

    kj::Promise<void> connectionChanged(ConnectionChangedContext context) override
    {
        auto connection = toConnection(context.getParams().getConnection());
        m_c->toGui([c = m_c, connection] { c->upsertConnection(connection); });
        return kj::READY_NOW;
    }

    kj::Promise<void> connectionRemoved(ConnectionRemovedContext context) override
    {
        auto uuid = text(context.getParams().getUuid());
        m_c->toGui([c = m_c, uuid] { c->removeConnection(uuid); });
        return kj::READY_NOW;
    }

    kj::Promise<void> event(EventContext context) override
    {
        const auto event = context.getParams().getEvent();
        if (event.isActivationFailed()) {
            const auto f = event.getActivationFailed();
            auto device = text(f.getDeviceId());
            auto uuid = text(f.getConnectionUuid());
            auto name = text(f.getName());
            auto reason = as<Network::StateReason>(f.getReason());
            m_c->toGui([c = m_c, device, uuid, name, reason] { c->applyActivationFailed(device, uuid, name, reason); });
        } else if (event.isConnected()) {
            auto uuid = text(event.getConnected());
            m_c->toGui([c = m_c, uuid] { c->applyConnected(uuid); });
        }
        return kj::READY_NOW;
    }

private:
    NetworkConnection *m_c;
};

// The shell's side of password requests (in the KJ thread): each ask() waits until the GUI answers
class Prompter final : public C::SecretPrompter::Server
{
public:
    Prompter(NetworkConnection *connection, std::shared_ptr<PendingAsks> pending)
        : m_c(connection)
        , m_pending(std::move(pending))
    {
    }

protected:
    kj::Promise<void> ask(AskContext context) override
    {
        auto request = toRequest(context.getParams().getRequest());
        auto paf = kj::newPromiseAndFulfiller<Reply>();
        (*m_pending)[request.id.toStdString()] = kj::mv(paf.fulfiller);
        m_c->toGui([c = m_c, request] { c->applySecretRequest(request); });
        return paf.promise.then([context](Reply reply) mutable {
            auto out = context.getResults().initReply();
            if (reply.cancelled) {
                out.setCancelled();
                return;
            }
            auto list = out.initSecrets(unsigned(reply.secrets.size()));
            for (unsigned i = 0; i < reply.secrets.size(); ++i) {
                list[i].setKey(reply.secrets[i].first);
                list[i].setValue(reply.secrets[i].second.c_str());
            }
        });
    }

    kj::Promise<void> cancel(CancelContext context) override
    {
        auto id = text(context.getParams().getId());
        auto it = m_pending->find(id.toStdString());
        if (it != m_pending->end()) {
            it->second->fulfill(Reply{});
            m_pending->erase(it);
        }
        m_c->toGui([c = m_c, id] { c->applySecretCancel(id); });
        return kj::READY_NOW;
    }

private:
    NetworkConnection *m_c;
    std::shared_ptr<PendingAsks> m_pending;
};

namespace {

void registerPrompter(NetworkConnection *connection, KjContext &context)
{
    auto request = context.service.registerPrompterRequest();
    request.setPrompter(kj::heap<Prompter>(connection, context.pending));
    auto sent = request.send();
    // Pipelining: the registration lives while this capability is kept
    context.registration = sent.getRegistration();
    context.tasks.add(sent.ignoreResult());
}

void cancelPending(KjContext &context)
{
    for (auto &[id, fulfiller] : *context.pending)
        fulfiller->fulfill(Reply{});
    context.pending->clear();
}

} // namespace

NetworkConnection::NetworkConnection(const QString &socketPath, QObject *parent)
    : NetworkSource(parent)
    , m_socketPath(socketPath)
{
    m_eventFd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    m_thread = std::thread([this] { run(); });
}

NetworkConnection::~NetworkConnection()
{
    m_quit = true;
    wake();
    m_thread.join();
    ::close(m_eventFd);
    if (NetworkSource::existingInstance() == this)
        NetworkSource::setInstance(nullptr);
}

QString NetworkConnection::defaultSocketPath()
{
    const QString explicitPath = qEnvironmentVariable("MAIA_NETWORK_SOCKET");
    if (!explicitPath.isEmpty())
        return explicitPath;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    QString display = qEnvironmentVariable("WAYLAND_DISPLAY", QStringLiteral("wayland-0"));
    // WAYLAND_DISPLAY may be an absolute path; only its name goes into ours
    display = QFileInfo(display).fileName();
    return runtime + QStringLiteral("/maia/network-") + display + QStringLiteral(".sock");
}

void NetworkConnection::wake()
{
    const uint64_t one = 1;
    [[maybe_unused]] auto written = ::write(m_eventFd, &one, sizeof(one));
}

void NetworkConnection::post(Task task, const Callback &done)
{
    if (!m_live) {
        if (done)
            done(unavailable());
        return;
    }
    {
        std::lock_guard lock(m_mutex);
        m_queue.push_back(std::move(task));
    }
    wake();
}

template<typename Request>
void NetworkConnection::sendControl(KjContext &context, Request request, Callback done)
{
    context.tasks.add(request.send().then(
        [this, done](auto &&response) {
            auto result = toResult(response.getResult());
            if (done)
                toGui([done, result] { done(result); });
        },
        [this, done](kj::Exception &&exception) {
            Result result{Network::ErrorCode::Unavailable, QString::fromUtf8(exception.getDescription().cStr())};
            if (done)
                toGui([done, result] { done(result); });
        }));
}

template<typename... Values>
void NetworkConnection::postWith(Task task, const ValueCallback<Values...> &done)
{
    if (!m_live) {
        if (done)
            done(unavailable(), Values{}...);
        return;
    }
    {
        std::lock_guard lock(m_mutex);
        m_queue.push_back(std::move(task));
    }
    wake();
}

template<typename Request, typename Read, typename... Values>
void NetworkConnection::sendControlWith(KjContext &context, Request request, Read read, ValueCallback<Values...> done)
{
    context.tasks.add(request.send().then(
        [this, read, done](auto &&response) {
            auto result = toResult(response.getResult());
            std::tuple<Values...> values = result.error == Network::ErrorCode::None ? read(response) : std::tuple<Values...>{};
            if (done)
                toGui([done, result, values] { std::apply([&](const Values &...v) { done(result, v...); }, values); });
        },
        [this, done](kj::Exception &&exception) {
            Result result{Network::ErrorCode::Unavailable, QString::fromUtf8(exception.getDescription().cStr())};
            if (done)
                toGui([done, result] { done(result, Values{}...); });
        }));
}

void NetworkConnection::run()
{
    kj::AsyncIoContext io = kj::setupAsyncIo();
    kj::UnixEventPort::FdObserver wakeObserver(io.unixEventPort, m_eventFd, kj::UnixEventPort::FdObserver::OBSERVE_READ);
    auto drainWake = [this] {
        uint64_t value;
        [[maybe_unused]] auto read = ::read(m_eventFd, &value, sizeof(value));
    };
    LogErrors errors;
    bool reportedFailure = false;

    while (!m_quit) {
        bool wasConnected = false;
        try {
            auto address = io.provider->getNetwork()
                               .parseAddress(kj::str("unix:", m_socketPath.toUtf8().constData()))
                               .wait(io.waitScope);
            auto stream = address->connect().wait(io.waitScope);
            capnp::TwoPartyClient client(*stream);
            kj::TaskSet tasks(errors);

            auto service = client.bootstrap().castAs<C::NetworkService>();
            // Pipelining: the control capability is usable at once, without waiting for the answer
            KjContext context{service, service.controlRequest().send().getControl(), tasks,
                              std::make_shared<PendingAsks>(), nullptr};

            auto watch = service.watchRequest();
            watch.setListener(kj::heap<Listener>(this));
            auto watched = watch.send();
            // Kept for the whole connection: releasing it would stop the listener
            auto subscription = watched.getSubscription();
            tasks.add(watched.ignoreResult());

            bool prompterRegistered = false;
            if (m_wantPrompter) {
                registerPrompter(this, context);
                prompterRegistered = true;
            }

            bool disconnected = false;
            auto disconnect = client.onDisconnect()
                                  .then([&] { disconnected = true; }, [&](kj::Exception &&) { disconnected = true; })
                                  .fork();

            wasConnected = true;
            m_live = true;
            reportedFailure = false;
            qInfo() << "[Maia.Network] connected to" << m_socketPath;

            while (!m_quit && !disconnected) {
                wakeObserver.whenBecomesReadable().exclusiveJoin(disconnect.addBranch()).wait(io.waitScope);
                drainWake();
                // The shell started or stopped asking for passwords
                if (m_wantPrompter != prompterRegistered) {
                    prompterRegistered = m_wantPrompter;
                    if (prompterRegistered) {
                        registerPrompter(this, context);
                    } else {
                        context.registration = nullptr;
                        cancelPending(context);
                    }
                }
                std::deque<Task> queue;
                {
                    std::lock_guard lock(m_mutex);
                    queue.swap(m_queue);
                }
                for (auto &task : queue) {
                    try {
                        task(context);
                    } catch (const kj::Exception &exception) {
                        qWarning() << "[Maia.Network]" << exception.getDescription().cStr();
                    }
                }
            }
            m_live = false;
            cancelPending(context);
        } catch (const kj::Exception &exception) {
            m_live = false;
            if (!reportedFailure)
                qWarning() << "[Maia.Network] no network service at" << m_socketPath << ":"
                           << exception.getDescription().cStr();
            reportedFailure = true;
        }

        if (wasConnected) {
            toGui([this] { setConnected(false); });
            qInfo() << "[Maia.Network] disconnected, retrying";
        }
        {
            std::lock_guard lock(m_mutex);
            m_queue.clear();
        }
        if (m_quit)
            break;
        io.provider->getTimer().afterDelay(1 * kj::SECONDS).exclusiveJoin(wakeObserver.whenBecomesReadable()).wait(io.waitScope);
        drainWake();
    }
}

// --- Commands (GUI thread) ---

void NetworkConnection::setWirelessEnabled(bool enabled, Callback done)
{
    post([this, enabled, done](KjContext &c) {
        auto request = c.control.setWirelessEnabledRequest();
        request.setEnabled(enabled);
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::requestScan(const QString &deviceId, Callback done)
{
    post([this, id = deviceId.toStdString(), done](KjContext &c) {
        auto request = c.control.requestScanRequest();
        request.setDeviceId(id.c_str());
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::connectNetwork(const QString &networkId, Callback done)
{
    post([this, id = networkId.toStdString(), done](KjContext &c) {
        auto request = c.control.connectRequest();
        request.setNetworkId(id.c_str());
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::activate(const QString &uuid, const QString &deviceId, Callback done)
{
    post([this, uuid = uuid.toStdString(), device = deviceId.toStdString(), done](KjContext &c) {
        auto request = c.control.activateRequest();
        request.setUuid(uuid.c_str());
        request.setDeviceId(device.c_str());
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::disconnectDevice(const QString &deviceId, Callback done)
{
    post([this, id = deviceId.toStdString(), done](KjContext &c) {
        auto request = c.control.disconnectRequest();
        request.setDeviceId(id.c_str());
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::forget(const QString &uuid, Callback done)
{
    post([this, uuid = uuid.toStdString(), done](KjContext &c) {
        auto request = c.control.forgetRequest();
        request.setUuid(uuid.c_str());
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::checkConnectivity(Callback done)
{
    post([this, done](KjContext &c) { sendControl(c, c.control.checkConnectivityRequest(), done); }, done);
}

void NetworkConnection::connectWithSettings(const QString &deviceId, const ConnectionSettingsData &settings,
                                            const QList<SecretData> &secrets, ValueCallback<QString> done)
{
    postWith([this, device = utf8(deviceId), settings, secrets, done](KjContext &c) {
        auto request = c.control.connectWithSettingsRequest();
        request.setDeviceId(device.c_str());
        writeSettings(request.initSettings(), settings);
        writeSecrets(request.initSecrets(unsigned(secrets.size())), secrets);
        sendControlWith(c, kj::mv(request), [](auto &response) { return std::tuple{text(response.getUuid())}; }, done);
    }, done);
}

void NetworkConnection::settings(const QString &uuid, ValueCallback<ConnectionSettingsData> done)
{
    postWith([this, uuid = utf8(uuid), done](KjContext &c) {
        auto request = c.control.settingsRequest();
        request.setUuid(uuid.c_str());
        sendControlWith(c, kj::mv(request), [](auto &response) { return std::tuple{toSettings(response.getSettings())}; }, done);
    }, done);
}

void NetworkConnection::updateSettings(const QString &uuid, const ConnectionSettingsData &settings,
                                       const QList<SecretData> &secrets, Callback done)
{
    post([this, uuid = utf8(uuid), settings, secrets, done](KjContext &c) {
        auto request = c.control.updateSettingsRequest();
        request.setUuid(uuid.c_str());
        writeSettings(request.initSettings(), settings);
        writeSecrets(request.initSecrets(unsigned(secrets.size())), secrets);
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::secrets(const QString &uuid, ValueCallback<QList<SecretData>> done)
{
    postWith([this, uuid = utf8(uuid), done](KjContext &c) {
        auto request = c.control.secretsRequest();
        request.setUuid(uuid.c_str());
        sendControlWith(c, kj::mv(request), [](auto &response) { return std::tuple{toSecrets(response.getSecrets())}; }, done);
    }, done);
}

void NetworkConnection::qrCode(const QString &uuid, ValueCallback<QrCodeData> done)
{
    postWith([this, uuid = utf8(uuid), done](KjContext &c) {
        auto request = c.control.qrCodeRequest();
        request.setUuid(uuid.c_str());
        sendControlWith(c, kj::mv(request), [](auto &response) {
            return std::tuple{QrCodeData{text(response.getText()), int(response.getSize()), bytes(response.getModules())}};
        }, done);
    }, done);
}

void NetworkConnection::startHotspot(const QString &deviceId, const QString &ssid, const QString &password,
                                     ValueCallback<QString, QString> done)
{
    postWith([this, device = utf8(deviceId), ssid = utf8(ssid), password = utf8(password), done](KjContext &c) {
        auto request = c.control.startHotspotRequest();
        request.setDeviceId(device.c_str());
        request.setSsid(ssid.c_str());
        request.setPasswordKind(password.empty() ? C::HotspotPasswordKind::GENERATE : C::HotspotPasswordKind::GIVEN);
        request.setPassword(password.c_str());
        sendControlWith(c, kj::mv(request), [](auto &response) {
            return std::tuple{text(response.getUuid()), text(response.getPassword())};
        }, done);
    }, done);
}

void NetworkConnection::stopHotspot(const QString &deviceId, Callback done)
{
    post([this, id = utf8(deviceId), done](KjContext &c) {
        auto request = c.control.stopHotspotRequest();
        request.setDeviceId(id.c_str());
        sendControl(c, kj::mv(request), done);
    }, done);
}

void NetworkConnection::setPrompterRegistered(bool registered)
{
    m_wantPrompter = registered;
    wake();
}

void NetworkConnection::answerSecrets(const QString &requestId, bool cancelled, const QList<SecretData> &secrets)
{
    Reply reply;
    reply.cancelled = cancelled;
    for (const auto &secret : secrets)
        reply.secrets.emplace_back(as<C::SecretKey>(secret.key), secret.value.toStdString());
    post([id = requestId.toStdString(), reply = std::move(reply)](KjContext &c) mutable {
        auto it = c.pending->find(id);
        if (it == c.pending->end())
            return; // already cancelled by the service
        it->second->fulfill(kj::mv(reply));
        c.pending->erase(it);
    });
}

} // namespace MaiaNetwork
