#include "Power.h"

#include <QDebug>
#include <QVariantMap>

#include <algorithm>

namespace MaiaPower {

namespace {

// A dragged slider sends at most this often; the service coalesces the rest anyway
constexpr int kSendInterval = 40;
// After the last local change, the service's value is shown again (the slider follows outside changes)
constexpr int kLocalHold = 500;

} // namespace

Power::Power(QObject *parent)
    : QObject(parent)
    , m_connection(PowerConnection::instance())
{
    m_sendTimer.setInterval(kSendInterval);
    m_sendTimer.setSingleShot(true);
    connect(&m_sendTimer, &QTimer::timeout, this, [this] {
        if (m_sendPending)
            sendBrightness();
    });
    m_localTimer.setInterval(kLocalHold + 20);
    m_localTimer.setSingleShot(true);
    connect(&m_localTimer, &QTimer::timeout, this, &Power::brightnessChanged);

    connect(m_connection, &PowerConnection::connectedChanged, this, &Power::connectedChanged);
    connect(m_connection, &PowerConnection::statusChanged, this, &Power::statusChanged);
    connect(m_connection, &PowerConnection::keyboardChanged, this, &Power::keyboardChanged);
    connect(m_connection, &PowerConnection::profilesChanged, this, &Power::profilesChanged);
    // Any display may be the built-in one
    connect(m_connection, &PowerConnection::displaysReset, this, &Power::brightnessChanged);
    connect(m_connection, &PowerConnection::displayChanged, this, &Power::brightnessChanged);
    connect(m_connection, &PowerConnection::displayAdded, this, &Power::brightnessChanged);
    connect(m_connection, &PowerConnection::displayRemoved, this, &Power::brightnessChanged);
    connect(m_connection, &PowerConnection::event, this, [this](int kind, const QString &batteryId, double percentage) {
        Q_EMIT event(EventKind(kind), batteryId, percentage);
    });
    connect(m_connection, &PowerConnection::requestFinished, this, [this](const QString &action, int error, const QString &message) {
        if (error == NoError)
            return;
        qWarning() << "[Maia.Power]" << action << "failed:" << message;
        if (action == QLatin1String("setBrightness") || action == QLatin1String("stepBrightness")) {
            // Show the screen's real brightness again
            m_localBrightness = -1;
            Q_EMIT brightnessChanged();
        }
        Q_EMIT requestFailed(action, Error(error), message);
    });
}

bool Power::connected() const
{
    return m_connection->isConnected();
}

// --- The battery ---

bool Power::upowerAvailable() const
{
    return m_connection->status().upowerAvailable;
}

bool Power::hasBattery() const
{
    return m_connection->status().upowerAvailable && m_connection->status().summary.present;
}

bool Power::onBattery() const
{
    return m_connection->status().onBattery;
}

bool Power::pluggedIn() const
{
    return hasBattery() && !m_connection->status().onBattery;
}

double Power::batteryPercentage() const
{
    return m_connection->status().summary.percentage;
}

Power::BatteryState Power::batteryState() const
{
    return BatteryState(m_connection->status().summary.state);
}

bool Power::charging() const
{
    const auto state = batteryState();
    return state == Charging || state == PendingCharge;
}

Power::WarningLevel Power::warningLevel() const
{
    return WarningLevel(m_connection->status().summary.warningLevel);
}

qint64 Power::timeToEmpty() const
{
    return m_connection->status().summary.timeToEmpty;
}

qint64 Power::timeToFull() const
{
    return m_connection->status().summary.timeToFull;
}

double Power::batteryCapacity() const
{
    return m_connection->status().summary.capacity;
}

bool Power::lidPresent() const
{
    return m_connection->status().lidPresent;
}

bool Power::lidClosed() const
{
    return m_connection->status().lidClosed;
}

// --- The screen ---

const DisplayInfo *Power::builtIn() const
{
    const auto &displays = m_connection->displays();
    for (const auto &display : displays) {
        if (display.kind == 0) // builtIn
            return &display;
    }
    return displays.isEmpty() ? nullptr : &displays.first();
}

bool Power::brightnessAvailable() const
{
    return builtIn() != nullptr;
}

double Power::brightness() const
{
    if (m_localBrightness >= 0 && m_sinceLocal.isValid() && m_sinceLocal.elapsed() < kLocalHold)
        return m_localBrightness;
    const DisplayInfo *display = builtIn();
    return display ? display->brightness : 0.0;
}

double Power::brightnessMinimum() const
{
    const DisplayInfo *display = builtIn();
    return display ? display->minimum : 0.0;
}

void Power::setBrightness(double brightness)
{
    if (!brightnessAvailable())
        return;
    brightness = std::clamp(brightness, brightnessMinimum(), 1.0);
    m_localBrightness = brightness;
    m_sinceLocal.start();
    Q_EMIT brightnessChanged();
    // The service's value is shown again once the user has stopped (one timer, restarted on every move)
    m_localTimer.start();
    if (m_sendTimer.isActive()) {
        m_sendPending = true;
    } else {
        sendBrightness();
    }
}

void Power::sendBrightness()
{
    m_sendPending = false;
    if (const DisplayInfo *display = builtIn())
        m_connection->setBrightness(display->id, m_localBrightness);
    m_sendTimer.start();
}

void Power::stepBrightness(int steps)
{
    m_localBrightness = -1;
    m_connection->stepBrightness(QString(), steps);
}

// --- The keyboard ---

bool Power::keyboardBrightnessAvailable() const
{
    return m_connection->keyboard().available;
}

double Power::keyboardBrightness() const
{
    return m_connection->keyboard().brightness;
}

void Power::setKeyboardBrightness(double brightness)
{
    if (!keyboardBrightnessAvailable())
        return;
    m_connection->setKeyboardBrightness(std::clamp(brightness, 0.0, 1.0));
}

int Power::keyboardBrightnessSteps() const
{
    return int(m_connection->keyboard().rawMaximum);
}

// --- Profiles ---

bool Power::profilesAvailable() const
{
    return m_connection->profiles().available;
}

Power::Profile Power::profile() const
{
    return Profile(m_connection->profiles().active);
}

void Power::setProfile(Profile profile)
{
    if (profile == this->profile() && m_connection->profiles().holds.isEmpty())
        return;
    m_connection->setProfile(int(profile));
}

QVariantList Power::profiles() const
{
    QVariantList list;
    for (int profile : m_connection->profiles().offered)
        list.append(QVariant::fromValue(Profile(profile)));
    return list;
}

Power::Degradation Power::performanceDegraded() const
{
    return Degradation(m_connection->profiles().degraded);
}

QVariantList Power::profileHolds() const
{
    QVariantList list;
    for (const auto &hold : m_connection->profiles().holds) {
        list.append(QVariantMap{
            {QStringLiteral("profile"), QVariant::fromValue(Profile(hold.profile))},
            {QStringLiteral("reason"), hold.reason},
            {QStringLiteral("applicationId"), hold.applicationId},
        });
    }
    return list;
}

} // namespace MaiaPower
