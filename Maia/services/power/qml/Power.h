#pragma once

// Power: the power state for QML, a singleton (one per QML engine, sharing the process's
// PowerConnection).
//
//   import Maia.Power
//
//   Text { text: Power.hasBattery ? Math.round(Power.batteryPercentage) + " %" : "" }
//   Slider { value: Power.brightness; onMoved: Power.brightness = value }
//   Connections { target: Power; function onEvent(kind) { if (kind === Power.BatteryLow) … } }
//
// The battery is the computer's as one (UPower's display device); the devices' batteries are in
// BatteriesModel. brightness is the built-in screen's (DisplaysModel has every display): set it
// freely while dragging, the requests are thinned out and the service's echoes do not move the
// slider back meanwhile. Requests that fail come back through requestFailed.

#include "PowerConnection.h"

#include <QElapsedTimer>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace MaiaPower {

class Power : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

    // The computer's battery and the charger (UPower)
    Q_PROPERTY(bool upowerAvailable READ upowerAvailable NOTIFY statusChanged)
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY statusChanged)
    Q_PROPERTY(bool onBattery READ onBattery NOTIFY statusChanged)
    Q_PROPERTY(bool pluggedIn READ pluggedIn NOTIFY statusChanged)
    Q_PROPERTY(double batteryPercentage READ batteryPercentage NOTIFY statusChanged)
    Q_PROPERTY(BatteryState batteryState READ batteryState NOTIFY statusChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY statusChanged)
    Q_PROPERTY(WarningLevel warningLevel READ warningLevel NOTIFY statusChanged)
    // Seconds, 0 = unknown
    Q_PROPERTY(qint64 timeToEmpty READ timeToEmpty NOTIFY statusChanged)
    Q_PROPERTY(qint64 timeToFull READ timeToFull NOTIFY statusChanged)
    Q_PROPERTY(QString batteryIconName READ batteryIconName NOTIFY statusChanged)
    // Health: the full capacity in percent of the design capacity, 0 = unknown
    Q_PROPERTY(double batteryCapacity READ batteryCapacity NOTIFY statusChanged)
    Q_PROPERTY(bool lidPresent READ lidPresent NOTIFY statusChanged)
    Q_PROPERTY(bool lidClosed READ lidClosed NOTIFY statusChanged)

    // The built-in screen
    Q_PROPERTY(bool brightnessAvailable READ brightnessAvailable NOTIFY brightnessChanged)
    Q_PROPERTY(double brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(double brightnessMinimum READ brightnessMinimum NOTIFY brightnessChanged)

    // The keyboard backlight
    Q_PROPERTY(bool keyboardBrightnessAvailable READ keyboardBrightnessAvailable NOTIFY keyboardChanged)
    Q_PROPERTY(double keyboardBrightness READ keyboardBrightness WRITE setKeyboardBrightness NOTIFY keyboardChanged)
    // The number of levels (0 .. steps), for a stepped control
    Q_PROPERTY(int keyboardBrightnessSteps READ keyboardBrightnessSteps NOTIFY keyboardChanged)

    // The power profile (power-profiles-daemon)
    Q_PROPERTY(bool profilesAvailable READ profilesAvailable NOTIFY profilesChanged)
    Q_PROPERTY(Profile profile READ profile WRITE setProfile NOTIFY profilesChanged)
    // The profiles this machine offers, as Profile values
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(Degradation performanceDegraded READ performanceDegraded NOTIFY profilesChanged)
    // Applications that hold a profile: [{ profile, reason, applicationId }]
    Q_PROPERTY(QVariantList profileHolds READ profileHolds NOTIFY profilesChanged)

public:
    // The numbers are those of the contract (power.capnp)
    enum BatteryState { StateUnknown, Charging, Discharging, Empty, Full, PendingCharge, PendingDischarge };
    Q_ENUM(BatteryState)
    enum WarningLevel { NoWarning, LowWarning, CriticalWarning, ActionWarning };
    Q_ENUM(WarningLevel)
    enum DeviceKind {
        BatteryDevice, UpsDevice, MouseDevice, KeyboardDevice, TouchpadDevice, GamingInputDevice, PenDevice,
        HeadsetDevice, HeadphonesDevice, SpeakersDevice, PhoneDevice, TabletDevice, MediaPlayerDevice,
        ComputerDevice, WearableDevice, OtherDevice
    };
    Q_ENUM(DeviceKind)
    enum Profile { PowerSaver, Balanced, Performance };
    Q_ENUM(Profile)
    enum Degradation { NotDegraded, LapDetected, HighOperatingTemperature, OtherDegradation };
    Q_ENUM(Degradation)
    enum EventKind { ChargerConnected, ChargerDisconnected, BatteryLow, BatteryCritical, BatteryAction, BatteryFull, DeviceBatteryLow };
    Q_ENUM(EventKind)
    enum Error { NoError, NotFound, NotAllowed, InvalidArgument, NotSupported, Unavailable, Failed };
    Q_ENUM(Error)

    explicit Power(QObject *parent = nullptr);

    bool connected() const;

    bool upowerAvailable() const;
    bool hasBattery() const;
    bool onBattery() const;
    bool pluggedIn() const;
    double batteryPercentage() const;
    BatteryState batteryState() const;
    bool charging() const;
    WarningLevel warningLevel() const;
    qint64 timeToEmpty() const;
    qint64 timeToFull() const;
    QString batteryIconName() const;
    double batteryCapacity() const;
    bool lidPresent() const;
    bool lidClosed() const;

    bool brightnessAvailable() const;
    double brightness() const;
    void setBrightness(double brightness);
    double brightnessMinimum() const;
    // Up (steps > 0) or down by 5 % each: keys, the wheel
    Q_INVOKABLE void stepBrightness(int steps);

    bool keyboardBrightnessAvailable() const;
    double keyboardBrightness() const;
    void setKeyboardBrightness(double brightness);
    int keyboardBrightnessSteps() const;

    bool profilesAvailable() const;
    Profile profile() const;
    void setProfile(Profile profile);
    QVariantList profiles() const;
    Degradation performanceDegraded() const;
    QVariantList profileHolds() const;

Q_SIGNALS:
    void connectedChanged();
    void statusChanged();
    void brightnessChanged();
    void keyboardChanged();
    void profilesChanged();
    // For notifications; batteryId is "" for the charger
    void event(MaiaPower::Power::EventKind kind, const QString &batteryId, double percentage);
    // action: "setBrightness", "stepBrightness", "setKeyboardBrightness", "setProfile"; message is for logs
    void requestFailed(const QString &action, MaiaPower::Power::Error error, const QString &message);

private:
    const DisplayInfo *builtIn() const;
    void sendBrightness();

    PowerConnection *m_connection;
    // The value the user is setting: shown at once, sent at most every kSendInterval
    double m_localBrightness = -1;
    QElapsedTimer m_sinceLocal;
    QTimer m_sendTimer;
    // After the last local change: show the service's value again
    QTimer m_localTimer;
    bool m_sendPending = false;
};

} // namespace MaiaPower
