#pragma once

// The connection of a process to the network service (maia-network-service), over Cap'n Proto.
//
// One per process (NetworkSource::instance()), shared by every QML object. Cap'n Proto runs in
// its own thread (KJ event loop), so the GUI thread never waits for the service:
//
//   GUI thread                          KJ thread
//   command ──► queue + eventfd ──────► request to the service
//   callback(result) ◄─── queued ─────── its answer
//   NetworkSource::upsert* ◄─ queued ─── NetworkListener call from the service
//   SecretPrompt ◄─────── queued ─────── SecretPrompter.ask() from the service
//   answerSecrets() ──► queue ─────────► fulfils the pending ask()
//
// The connection is retried every second while the service is not there (its start, a crash);
// meanwhile the state is empty and commands answer Unavailable. The prompter registration is
// renewed on every new connection while the shell wants it.
//
// Socket: $MAIA_NETWORK_SOCKET, or $XDG_RUNTIME_DIR/maia/network-$WAYLAND_DISPLAY.sock (the same
// rule as the service).

#include "NetworkSource.h"

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace MaiaNetwork {

struct KjContext;

class NetworkConnection final : public NetworkSource
{
    Q_OBJECT

public:
    explicit NetworkConnection(const QString &socketPath, QObject *parent = nullptr);
    ~NetworkConnection() override;

    static QString defaultSocketPath();
    QString socketPath() const { return m_socketPath; }

    void setWirelessEnabled(bool enabled, Callback done = {}) override;
    void requestScan(const QString &deviceId, Callback done = {}) override;
    void connectNetwork(const QString &networkId, Callback done = {}) override;
    void activate(const QString &uuid, const QString &deviceId, Callback done = {}) override;
    void disconnectDevice(const QString &deviceId, Callback done = {}) override;
    void forget(const QString &uuid, Callback done = {}) override;
    void checkConnectivity(Callback done = {}) override;
    void connectWithSettings(const QString &deviceId, const ConnectionSettingsData &settings, const QList<SecretData> &secrets,
                             ValueCallback<QString> done = {}) override;
    void settings(const QString &uuid, ValueCallback<ConnectionSettingsData> done) override;
    void updateSettings(const QString &uuid, const ConnectionSettingsData &settings, const QList<SecretData> &secrets,
                        Callback done = {}) override;
    void secrets(const QString &uuid, ValueCallback<QList<SecretData>> done) override;
    void qrCode(const QString &uuid, ValueCallback<QrCodeData> done) override;
    void startHotspot(const QString &deviceId, const QString &ssid, const QString &password,
                      ValueCallback<QString, QString> done = {}) override;
    void stopHotspot(const QString &deviceId, Callback done = {}) override;
    void setPrompterRegistered(bool registered) override;
    void answerSecrets(const QString &requestId, bool cancelled, const QList<SecretData> &secrets) override;

private:
    using Task = std::function<void(KjContext &)>;

    friend class Listener;
    friend class Prompter;

    void run();
    // Runs the task in the KJ thread; without a connection the callback gets Unavailable at once
    void post(Task task, const Callback &done = {});
    void wake();
    // Runs f in the GUI thread (dropped when this object is gone)
    template<typename F>
    void toGui(F f)
    {
        QMetaObject::invokeMethod(this, std::move(f), Qt::QueuedConnection);
    }
    // Sends a control request and hands its Result to `done` in the GUI thread
    template<typename Request>
    void sendControl(KjContext &context, Request request, Callback done);
    // Sends a control request; `read` turns its response into the values for `done`, in the KJ
    // thread (the response is gone afterwards), then `done` runs in the GUI thread
    template<typename Request, typename Read, typename... Values>
    void sendControlWith(KjContext &context, Request request, Read read, ValueCallback<Values...> done);
    // Without a connection: `done` gets Unavailable and empty values at once
    template<typename... Values>
    void postWith(Task task, const ValueCallback<Values...> &done);

    const QString m_socketPath;
    std::thread m_thread;
    std::atomic<bool> m_quit{false};
    std::atomic<bool> m_wantPrompter{false};
    // The KJ thread is connected; set there, read by post() in the GUI thread
    std::atomic<bool> m_live{false};
    int m_eventFd = -1;
    std::mutex m_mutex;
    std::deque<Task> m_queue;
};

} // namespace MaiaNetwork
