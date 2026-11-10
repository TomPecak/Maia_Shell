#include "SessionChildrenModel.h"

namespace MaiaSession {

SessionChildrenModel::SessionChildrenModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_connection(SessionConnection::instance())
    , m_children(m_connection->children())
{
    connect(m_connection, &SessionConnection::childrenReset, this, [this] {
        beginResetModel();
        m_children = m_connection->children();
        endResetModel();
    });
    connect(m_connection, &SessionConnection::childAdded, this, [this](int row) {
        beginInsertRows({}, row, row);
        m_children = m_connection->children();
        endInsertRows();
    });
    connect(m_connection, &SessionConnection::childChanged, this, [this](int row) {
        m_children = m_connection->children();
        Q_EMIT dataChanged(index(row), index(row));
    });
}

int SessionChildrenModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_children.size());
}

QVariant SessionChildrenModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid))
        return {};
    const ChildInfo &child = m_children[index.row()];
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return child.name;
    case KindRole:
        return child.kind;
    case StateRole:
        return child.state;
    case PidRole:
        return child.pid;
    case RestartsRole:
        return child.restarts;
    case LastExitRole:
        return child.lastExit;
    }
    return {};
}

QHash<int, QByteArray> SessionChildrenModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {KindRole, "kind"},
        {StateRole, "state"},
        {PidRole, "pid"},
        {RestartsRole, "restarts"},
        {LastExitRole, "lastExit"},
    };
}

void SessionChildrenModel::restart(const QString &name)
{
    m_connection->restartChild(name);
}

} // namespace MaiaSession
