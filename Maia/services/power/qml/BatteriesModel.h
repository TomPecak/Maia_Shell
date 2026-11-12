#pragma once

// BatteriesModel: the batteries the system knows, the computer's and the devices' (a mouse,
// headphones, a phone), for a list of devices and their levels.
//
//   ListView { model: BatteriesModel { devicesOnly: true } delegate: Text { text: model.modelName + " " + model.percentage } }
//
// Roles: id, kind (Power.DeviceKind), vendor, modelName (not "model": a role of that name hides a
// delegate's model object), present, powerSupply (powers the computer), percentage, state
// (Power.BatteryState), warningLevel (Power.WarningLevel), timeToEmpty, timeToFull (seconds),
// energyRate (watts), capacity (health, %), iconName.

#include "PowerConnection.h"

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

namespace MaiaPower {

class BatteriesModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    // Only the devices' batteries, without the computer's own
    Q_PROPERTY(bool devicesOnly READ devicesOnly WRITE setDevicesOnly NOTIFY devicesOnlyChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1, KindRole, VendorRole, ModelNameRole, PresentRole, PowerSupplyRole, PercentageRole,
        StateRole, WarningLevelRole, TimeToEmptyRole, TimeToFullRole, EnergyRateRole, CapacityRole, IconNameRole
    };
    Q_ENUM(Role)

    explicit BatteriesModel(QObject *parent = nullptr);

    bool devicesOnly() const { return m_devicesOnly; }
    void setDevicesOnly(bool devicesOnly);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

Q_SIGNALS:
    void devicesOnlyChanged();
    void countChanged();

private:
    void reload();
    bool accepts(const BatteryInfo &battery) const;

    PowerConnection *m_connection;
    bool m_devicesOnly = false;
    QList<BatteryInfo> m_batteries;
};

} // namespace MaiaPower
