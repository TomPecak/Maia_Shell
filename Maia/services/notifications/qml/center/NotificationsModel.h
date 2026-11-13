#pragma once

// NotificationsModel: every notification of the session, the newest first (a notification that is
// replaced comes to the top), for the notification center of a shell.
//
//   ListView { model: NotificationsModel {} delegate: Card { title: model.summary … } }
//
// A batch of the service is one update: removed rows go in contiguous ranges, new ones come in one
// insertion at the top, a replaced one moves to the top, the rest change in place. Roles: see
// NotificationRoles.h.

#include "NotificationData.h"

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class NotificationsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    explicit NotificationsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE int rowOf(uint notificationId) const;

Q_SIGNALS:
    void countChanged();

private:
    void reload();
    void applyBatch(const QList<NotificationData> &changed, const QList<quint32> &removed);
    void reindex();

    QList<NotificationData> m_items;
    QHash<quint32, int> m_rows;
};

} // namespace MaiaNotifications
