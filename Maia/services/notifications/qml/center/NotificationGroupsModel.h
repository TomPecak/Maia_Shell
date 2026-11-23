#pragma once

// NotificationGroupsModel: the notifications of the session by application, for a notification
// center that stacks them (as on iPadOS).
//
//   NotificationGroupsModel { id: groups; seenUntil: lastOpened }
//   ListView { model: groups; delegate: Card { stacked: model.groupHead && !model.groupExpanded … } }
//   Badge { count: groups.unseen }
//
// One flat list: the application with the newest notification first; of each application its newest
// notification (the head), and the others only while the group is expanded. So expanding a group
// inserts rows and a view can animate them, and a view of a long list creates only what it shows.
//
// Every update is the smallest set of removals, moves and insertions. Roles: those of
// NotificationRoles.h, and groupKey (the application: its desktop entry, else its name), groupCount
// (its notifications), groupHead (this row is its newest), groupExpanded.

#include "NotificationData.h"
#include "NotificationRoles.h"

#include <QAbstractListModel>
#include <QSet>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class NotificationGroupsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    // The rows shown now
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    // Every notification, those folded into their group too
    Q_PROPERTY(int total READ total NOTIFY totalChanged)
    // Notifications are "seen" up to this moment (ms since 1970): the shell sets it when the user
    // looks at the list
    Q_PROPERTY(double seenUntil READ seenUntil WRITE setSeenUntil NOTIFY seenUntilChanged)
    // How many arrived after it
    Q_PROPERTY(int unseen READ unseen NOTIFY unseenChanged)

public:
    enum Role {
        GroupKeyRole = NotificationRoles::SuppressSoundRole + 1,
        GroupCountRole,
        GroupHeadRole,
        GroupExpandedRole,
    };

    explicit NotificationGroupsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int total() const { return m_total; }
    double seenUntil() const { return m_seenUntil; }
    void setSeenUntil(double ms);
    int unseen() const { return m_unseen; }

    Q_INVOKABLE void setGroupExpanded(const QString &key, bool expanded);
    Q_INVOKABLE void toggleGroup(const QString &key);
    Q_INVOKABLE void collapseAll();
    // Every notification of the application, critical ones too: the user asked for this one
    Q_INVOKABLE void dismissGroup(const QString &key);

Q_SIGNALS:
    void countChanged();
    void totalChanged();
    void seenUntilChanged();
    void unseenChanged();

private:
    struct Row {
        NotificationData data;
        QString key;
        int groupCount = 0;
        bool head = false;
        bool expanded = false;
    };

    void reload();
    void applyBatch(const QList<NotificationData> &changed, const QList<quint32> &removed);
    // The rows as they should be now
    QList<Row> arranged();
    // Brings the rows there; `changed`: notifications whose content is new
    void update(const QList<Row> &target, const QSet<quint32> &changed);
    void recount();

    QList<Row> m_rows;
    QSet<QString> m_expanded;
    int m_total = 0;
    double m_seenUntil = 0;
    int m_unseen = 0;
};

} // namespace MaiaNotifications
