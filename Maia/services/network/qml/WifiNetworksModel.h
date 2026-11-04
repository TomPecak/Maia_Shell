#pragma once

// The networks in reach, for a Wi-Fi menu or the Wi-Fi page:
//
//   ListView {
//       model: WifiNetworksModel { limit: 8 }          // quick settings: the first 8
//       delegate: NetworkRow {
//           required property string name
//           required property int signalLevel
//           required property bool secure
//           required property bool active
//           required property string networkId
//           onClicked: ListView.view.model.connectNetwork(networkId)
//       }
//   }
//
// Order, as in GNOME (docs/gnome-wifi-features.md, sections 2-3): the connected network first,
// then saved before new, stronger before weaker, secured before open, then by name. Rows move
// (not reset) when the order changes, so delegates can animate.

#include "QmlHelpers.h"

#include <QJSValue>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

class WifiNetworksModel : public SortedIdModel
{
    Q_OBJECT
    QML_ELEMENT

    // Only the networks of this device ("" = all devices)
    Q_PROPERTY(QString deviceId READ deviceId WRITE setDeviceId NOTIFY deviceIdChanged)
    // At most this many rows (0 = all)
    Q_PROPERTY(int limit READ limit WRITE setLimit NOTIFY limitChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        NetworkIdRole = Qt::UserRole + 1,
        NameRole,
        DeviceIdRole,
        SecurityRole,
        SecureRole,          // asks for a password (padlock)
        EnterpriseRole,      // needs 802.1X details before connecting
        StrengthRole,
        SignalLevelRole,     // 0..4
        FrequencyRole,
        BandsRole,
        KnownRole,           // a saved profile fits it
        ConnectionUuidRole,  // the first fitting profile, "" for a new network
        ActiveRole,          // connected or connecting
        ConnectingRole,      // connecting or waiting for a password
    };
    Q_ENUM(Role)

    explicit WifiNetworksModel(QObject *parent = nullptr);

    QString deviceId() const { return m_deviceId; }
    void setDeviceId(const QString &deviceId);
    int limit() const { return m_limit; }
    void setLimit(int limit);

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Connects (saved profile, or a new one; secrets are asked through the shell's SecretPrompt).
    // Enterprise networks without a profile answer InvalidArgument: they need their details first.
    Q_INVOKABLE void connectNetwork(const QString &networkId, const QJSValue &callback = {});
    // The values of one network as an object (role names as keys), {} when it is not in the model
    Q_INVOKABLE QVariantMap get(const QString &networkId) const;

Q_SIGNALS:
    void deviceIdChanged();
    void limitChanged();

private:
    void resort();
    bool connectingTo(const NetworkData &network) const;

    NetworkSource *m_source;
    QString m_deviceId;
    int m_limit = 0;
};

} // namespace MaiaNetwork
