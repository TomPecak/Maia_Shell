#pragma once

// The connection of a process to the power service (maia-power-service), over Cap'n Proto.
//
// One per process (instance()), shared by Power, BatteriesModel, DisplaysModel and ProfileHold.
// Cap'n Proto runs in its own thread (KJ event loop), so the GUI thread never waits for the service:
//
//   GUI thread                          KJ thread
//   setBrightness() ──► queue + eventfd ──► request to the service
//   state ◄────────── queued ─────────────── PowerListener call from the service
//
// The connection is retried every second while the service is not there (its start, a crash); the
// last known state stays meanwhile (connected is false). Profile holds are made again after a
// reconnection by their ProfileHold objects.
//
// Socket: $MAIA_POWER_SOCKET, or $XDG_RUNTIME_DIR/maia/power-$WAYLAND_DISPLAY.sock (the same rule
// as the service).

#include <QList>
#include <QObject>
#include <QString>

#include <atomic>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

namespace MaiaPower {

struct KjContext;

// The values of the contract, plain; the numbers are those of the enums of Power (Power.h)
struct BatteryInfo {
    QString id;
    int kind = 0;
    QString vendor;
    QString model;
    bool present = false;
    bool powerSupply = false;
    double percentage = 0;
    int state = 0;
    int warningLevel = 0;
    qint64 timeToEmpty = 0;
    qint64 timeToFull = 0;
    double energyRate = 0;
    double capacity = 0;

    bool operator==(const BatteryInfo &) const = default;
};

struct StatusInfo {
    bool upowerAvailable = false;
    bool onBattery = false;
    bool lidPresent = false;
    bool lidClosed = false;
    BatteryInfo summary;

    bool operator==(const StatusInfo &) const = default;
};

struct DisplayInfo {
    QString id;
    int kind = 0;
    QString device;
    double brightness = 0;
    quint32 rawBrightness = 0;
    quint32 rawMaximum = 0;
    double minimum = 0;

    bool operator==(const DisplayInfo &) const = default;
};

struct KeyboardInfo {
    bool available = false;
    double brightness = 0;
    quint32 rawBrightness = 0;
    quint32 rawMaximum = 0;

    bool operator==(const KeyboardInfo &) const = default;
};

struct HoldInfo {
    int profile = 0;
    QString reason;
    QString applicationId;

    bool operator==(const HoldInfo &) const = default;
};

struct ProfilesInfo {
    bool available = false;
    int active = 1;
    QList<int> offered;
    int degraded = 0;
    QList<HoldInfo> holds;

    bool operator==(const ProfilesInfo &) const = default;
};

class PowerConnection final : public QObject
{
    Q_OBJECT

public:
    explicit PowerConnection(const QString &socketPath, QObject *parent = nullptr);
    ~PowerConnection() override;

    // The connection of this process, created on first use
    static PowerConnection *instance();
    static QString defaultSocketPath();

    QString socketPath() const { return m_socketPath; }

    bool isConnected() const { return m_connected; }
    const StatusInfo &status() const { return m_status; }
    const QList<BatteryInfo> &batteries() const { return m_batteries; }
    const QList<DisplayInfo> &displays() const { return m_displays; }
    const KeyboardInfo &keyboard() const { return m_keyboard; }
    const ProfilesInfo &profiles() const { return m_profiles; }

    // Requests; the outcome arrives through requestFinished (error 0 = success). The action names
    // are those of requestFailed in Power.
    void setBrightness(const QString &displayId, double brightness);
    void stepBrightness(const QString &displayId, int steps);
    void setKeyboardBrightness(double brightness);
    void setProfile(int profile);

    // Holds a profile until releaseProfile(id); the outcome arrives through holdFinished(id, error)
    int holdProfile(int profile, const QString &reason, const QString &applicationId);
    void releaseProfile(int id);

Q_SIGNALS:
    void connectedChanged();
    void statusChanged();
    void keyboardChanged();
    void profilesChanged();
    // The whole list (a new connection) or one battery / display
    void batteriesReset();
    void batteryChanged(int row);
    void batteryAdded(int row);
    void batteryRemoved(int row);
    void displaysReset();
    void displayChanged(int row);
    void displayAdded(int row);
    void displayRemoved(int row);
    void event(int kind, const QString &batteryId, double percentage);
    void requestFinished(const QString &action, int error, const QString &message);
    void holdFinished(int id, int error, const QString &message);

private:
    using Task = std::function<void(KjContext &)>;

    friend class Listener;

    // GUI thread
    void setConnected(bool connected);
    void applySnapshot(const StatusInfo &status, const QList<BatteryInfo> &batteries, const QList<DisplayInfo> &displays,
                       const KeyboardInfo &keyboard, const ProfilesInfo &profiles);
    void applyStatus(const StatusInfo &status);
    void applyBattery(const BatteryInfo &battery);
    void removeBattery(const QString &id);
    void applyDisplay(const DisplayInfo &display);
    void removeDisplay(const QString &id);
    void applyKeyboard(const KeyboardInfo &keyboard);
    void applyProfiles(const ProfilesInfo &profiles);

    void run();
    void post(Task task);
    void wake();
    template<typename F>
    void toGui(F f)
    {
        QMetaObject::invokeMethod(this, std::move(f), Qt::QueuedConnection);
    }

    const QString m_socketPath;
    bool m_connected = false;
    StatusInfo m_status;
    QList<BatteryInfo> m_batteries;
    QList<DisplayInfo> m_displays;
    KeyboardInfo m_keyboard;
    ProfilesInfo m_profiles;
    int m_nextHold = 0;

    std::thread m_thread;
    std::atomic<bool> m_quit{false};
    int m_eventFd = -1;
    std::mutex m_mutex;
    std::deque<Task> m_queue;
};

} // namespace MaiaPower
