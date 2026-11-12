#include "DisplaysModel.h"

namespace MaiaPower {

DisplaysModel::DisplaysModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_connection(PowerConnection::instance())
{
    // The rows are the connection's list itself: its signals come right after it changed
    connect(m_connection, &PowerConnection::displaysReset, this, [this] {
        beginResetModel();
        endResetModel();
        Q_EMIT countChanged();
    });
    connect(m_connection, &PowerConnection::displayAdded, this, [this](int row) {
        beginInsertRows({}, row, row);
        endInsertRows();
        Q_EMIT countChanged();
    });
    connect(m_connection, &PowerConnection::displayRemoved, this, [this](int) {
        // The row is gone already: a reset is the honest change
        beginResetModel();
        endResetModel();
        Q_EMIT countChanged();
    });
    connect(m_connection, &PowerConnection::displayChanged, this, [this](int row) { Q_EMIT dataChanged(index(row), index(row)); });
}

int DisplaysModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_connection->displays().size());
}

QVariant DisplaysModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid))
        return {};
    const DisplayInfo &d = m_connection->displays()[index.row()];
    switch (role) {
    case Qt::DisplayRole:
    case IdRole:
        return d.id;
    case KindRole:
        return d.kind;
    case DeviceRole:
        return d.device;
    case BrightnessRole:
        return d.brightness;
    case MinimumRole:
        return d.minimum;
    }
    return {};
}

QHash<int, QByteArray> DisplaysModel::roleNames() const
{
    return {{IdRole, "id"}, {KindRole, "kind"}, {DeviceRole, "device"}, {BrightnessRole, "brightness"}, {MinimumRole, "minimum"}};
}

void DisplaysModel::setBrightness(const QString &id, double brightness)
{
    m_connection->setBrightness(id, brightness);
}

void DisplaysModel::stepBrightness(const QString &id, int steps)
{
    m_connection->stepBrightness(id, steps);
}

} // namespace MaiaPower
