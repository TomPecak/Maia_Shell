#pragma once

// SessionChildrenModel: the processes of the session and their state, for a debug page.
//
// Roles: name, kind ("compositor", "shell", "maiaService", "kdeService", "helper"), state
// ("waiting", "running", "restarting", "failed", "stopped"), pid (0 when not running), restarts,
// lastExit ("exit code 1", "signal 11 (SIGSEGV)"). restart(name) starts a child again by hand.

#include "SessionConnection.h"

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

namespace MaiaSession {

class SessionChildrenModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

public:
    enum Role { NameRole = Qt::UserRole + 1, KindRole, StateRole, PidRole, RestartsRole, LastExitRole };
    Q_ENUM(Role)

    explicit SessionChildrenModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void restart(const QString &name);

private:
    SessionConnection *m_connection;
    QList<ChildInfo> m_children;
};

} // namespace MaiaSession
