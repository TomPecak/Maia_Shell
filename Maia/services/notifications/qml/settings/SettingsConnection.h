#pragma once

// The connection of Maia Settings to the NotificationSettings of the notification service. One per
// process (instance()), shared by NotificationSettings and AppNotificationsModel.
//
// The service sends all of the settings first and again on every change (they are small and change
// rarely); they are read into Qt values in the KJ thread and applied in the GUI thread. The last
// settings stay while the service is away (connected is false).
//
// Socket: $MAIA_NOTIFICATIONS_SETTINGS_SOCKET, or
//         $XDG_RUNTIME_DIR/maia/notifications-settings-$WAYLAND_DISPLAY.sock

#include "Contract.h"
#include "ServiceLink.h"

#include <optional>

namespace MaiaNotifications {

class SettingsConnection final : public ServiceLink
{
    Q_OBJECT

public:
    explicit SettingsConnection(const QString &socketPath, QObject *parent = nullptr);
    ~SettingsConnection() override;

    static SettingsConnection *instance();
    static QString defaultSocketPath();

    const SettingsData &settings() const { return m_settings; }
    // The settings have come once (until then they are the defaults)
    bool hasSettings() const { return m_hasSettings; }

    // until: ms since 1970, 0 = until turned off
    void setDoNotDisturb(bool enabled, qint64 until);
    void setLockScreenNotifications(bool enabled);
    void setAppEnabled(const QString &key, bool enabled);

Q_SIGNALS:
    void settingsChanged();

protected:
    void connected(capnp::Capability::Client bootstrap, kj::TaskSet &tasks) override;
    void disconnected() override;

private:
    friend class SettingsListenerImpl;

    // GUI thread
    void apply(const SettingsData &settings);

    SettingsData m_settings;
    bool m_hasSettings = false;

    // KJ thread
    std::optional<C::NotificationSettings::Client> m_service;
    std::optional<C::Subscription::Client> m_subscription;
};

} // namespace MaiaNotifications
