#include "BatteriesModel.h"

namespace MaiaPower {

BatteriesModel::BatteriesModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_connection(PowerConnection::instance())
{
    reload();
    // Batteries come and go rarely: the list is rebuilt, and kept rows keep their delegates when
    // only values changed
    auto update = [this] {
        QList<BatteryInfo> next;
        for (const auto &battery : m_connection->batteries()) {
            if (accepts(battery))
                next.append(battery);
        }
        bool sameIds = next.size() == m_batteries.size();
        for (int i = 0; sameIds && i < next.size(); ++i)
            sameIds = next[i].id == m_batteries[i].id;
        if (!sameIds) {
            beginResetModel();
            m_batteries = next;
            endResetModel();
            Q_EMIT countChanged();
            return;
        }
        for (int i = 0; i < next.size(); ++i) {
            if (!(next[i] == m_batteries[i])) {
                m_batteries[i] = next[i];
                Q_EMIT dataChanged(index(i), index(i));
            }
        }
    };
    connect(m_connection, &PowerConnection::batteriesReset, this, update);
    connect(m_connection, &PowerConnection::batteryAdded, this, update);
    connect(m_connection, &PowerConnection::batteryChanged, this, update);
    connect(m_connection, &PowerConnection::batteryRemoved, this, update);
}

bool BatteriesModel::accepts(const BatteryInfo &battery) const
{
    return !m_devicesOnly || !battery.powerSupply;
}

void BatteriesModel::reload()
{
    beginResetModel();
    m_batteries.clear();
    for (const auto &battery : m_connection->batteries()) {
        if (accepts(battery))
            m_batteries.append(battery);
    }
    endResetModel();
    Q_EMIT countChanged();
}

void BatteriesModel::setDevicesOnly(bool devicesOnly)
{
    if (m_devicesOnly == devicesOnly)
        return;
    m_devicesOnly = devicesOnly;
    reload();
    Q_EMIT devicesOnlyChanged();
}

int BatteriesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_batteries.size());
}

QVariant BatteriesModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid))
        return {};
    const BatteryInfo &b = m_batteries[index.row()];
    switch (role) {
    case IdRole:
        return b.id;
    case KindRole:
        return b.kind;
    case VendorRole:
        return b.vendor;
    case Qt::DisplayRole:
    case ModelNameRole:
        return b.model;
    case PresentRole:
        return b.present;
    case PowerSupplyRole:
        return b.powerSupply;
    case PercentageRole:
        return b.percentage;
    case StateRole:
        return b.state;
    case WarningLevelRole:
        return b.warningLevel;
    case TimeToEmptyRole:
        return b.timeToEmpty;
    case TimeToFullRole:
        return b.timeToFull;
    case EnergyRateRole:
        return b.energyRate;
    case CapacityRole:
        return b.capacity;
    }
    return {};
}

QHash<int, QByteArray> BatteriesModel::roleNames() const
{
    return {
        {IdRole, "id"}, {KindRole, "kind"}, {VendorRole, "vendor"}, {ModelNameRole, "modelName"}, {PresentRole, "present"},
        {PowerSupplyRole, "powerSupply"}, {PercentageRole, "percentage"}, {StateRole, "state"},
        {WarningLevelRole, "warningLevel"}, {TimeToEmptyRole, "timeToEmpty"}, {TimeToFullRole, "timeToFull"},
        {EnergyRateRole, "energyRate"}, {CapacityRole, "capacity"},
    };
}

} // namespace MaiaPower
