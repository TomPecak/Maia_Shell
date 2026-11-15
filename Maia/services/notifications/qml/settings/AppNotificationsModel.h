#pragma once

// AppNotificationsModel: the applications that send notifications (those that have sent one and
// those that declare it), with whether the user lets them, sorted by name.
//
//   Repeater { model: AppNotificationsModel {}
//              SettingsCard { iconName: model.appIcon; title: model.appName
//                             LSwitch { checked: model.enabled
//                                       onToggled: NotificationSettings.setAppEnabled(model.key, checked) } } }
//
// A change of one application (its switch) changes its row only; the rows are new only when
// applications come or go.

#include "NotificationData.h"

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class AppNotificationsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        KeyRole = Qt::UserRole + 1,
        DesktopEntryRole,
        AppNameRole,
        AppIconRole,
        EnabledRole,
        SentRole,
        DeclaredRole,
    };
    Q_ENUM(Role)

    explicit AppNotificationsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // By name, as people read it (locale aware, case does not matter), then by key
    static QList<AppNotificationsData> sorted(QList<AppNotificationsData> apps);

Q_SIGNALS:
    void countChanged();

private:
    void update();

    QList<AppNotificationsData> m_apps;
};

} // namespace MaiaNotifications
