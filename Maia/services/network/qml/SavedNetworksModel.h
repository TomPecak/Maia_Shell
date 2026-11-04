#pragma once

// The saved Wi-Fi profiles (docs/gnome-wifi-features.md, section 6), the last used first. Hotspot
// profiles are left out: they belong to the hotspot, not to the list of networks.
//
// Forgetting with undo is the frontend's: it hides the row and calls forget() only once its undo
// message is gone, as GNOME does.

#include "QmlHelpers.h"

#include <QJSValue>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

class SavedNetworksModel : public SortedIdModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        UuidRole = Qt::UserRole + 1,
        NameRole,
        SsidRole,           // the SSID as text
        SecurityRole,
        SecureRole,
        HiddenRole,
        AutoconnectRole,
        MeteredRole,
        AvailableToAllRole,
        LastUsedRole,       // Date, invalid when never used
        ActiveRole,
        ActiveDeviceIdRole,
        InRangeRole,        // one of the networks in reach fits it
        StrengthRole,       // of that network, 0 when out of reach
        SignalLevelRole,
        QrSupportedRole,
    };
    Q_ENUM(Role)

    explicit SavedNetworksModel(QObject *parent = nullptr);

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void forget(const QString &uuid, const QJSValue &callback = {});
    // Connects with the profile on its device (deviceId "" = NetworkManager chooses)
    Q_INVOKABLE void activate(const QString &uuid, const QString &deviceId = {}, const QJSValue &callback = {});
    Q_INVOKABLE QVariantMap get(const QString &uuid) const;

private:
    void resort();
    // The strongest network in reach this profile fits
    const NetworkData *networkOf(const QString &uuid) const;

    NetworkSource *m_source;
};

} // namespace MaiaNetwork
