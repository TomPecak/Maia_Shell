#include "AppNotificationsModel.h"

#include "SettingsConnection.h"

#include <algorithm>

namespace MaiaNotifications {

AppNotificationsModel::AppNotificationsModel(QObject *parent)
    : QAbstractListModel(parent)
{
    auto *connection = SettingsConnection::instance();
    connect(connection, &SettingsConnection::settingsChanged, this, &AppNotificationsModel::update);
    m_apps = sorted(connection->settings().apps);
}

QList<AppNotificationsData> AppNotificationsModel::sorted(QList<AppNotificationsData> apps)
{
    std::sort(apps.begin(), apps.end(), [](const AppNotificationsData &a, const AppNotificationsData &b) {
        const int byName = QString::localeAwareCompare(a.appName.toCaseFolded(), b.appName.toCaseFolded());
        return byName != 0 ? byName < 0 : a.key < b.key;
    });
    return apps;
}

void AppNotificationsModel::update()
{
    const QList<AppNotificationsData> apps = sorted(SettingsConnection::instance()->settings().apps);
    const bool sameRows = apps.size() == m_apps.size()
        && std::equal(apps.cbegin(), apps.cend(), m_apps.cbegin(), [](const auto &a, const auto &b) { return a.key == b.key; });
    if (!sameRows) {
        beginResetModel();
        m_apps = apps;
        endResetModel();
        Q_EMIT countChanged();
        return;
    }
    // The same applications: only the rows that changed (a switch keeps its delegate)
    for (int row = 0; row < apps.size(); ++row) {
        if (apps[row] == m_apps[row])
            continue;
        m_apps[row] = apps[row];
        Q_EMIT dataChanged(index(row), index(row));
    }
}

int AppNotificationsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_apps.size());
}

QVariant AppNotificationsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid))
        return {};
    const AppNotificationsData &app = m_apps[index.row()];
    switch (role) {
    case KeyRole:
        return app.key;
    case DesktopEntryRole:
        return app.desktopEntry;
    case Qt::DisplayRole:
    case AppNameRole:
        return app.appName;
    case AppIconRole:
        return app.appIcon;
    case EnabledRole:
        return app.enabled;
    case SentRole:
        return app.sent;
    case DeclaredRole:
        return app.declared;
    }
    return {};
}

QHash<int, QByteArray> AppNotificationsModel::roleNames() const
{
    return {
        {KeyRole, "key"},
        {DesktopEntryRole, "desktopEntry"},
        {AppNameRole, "appName"},
        {AppIconRole, "appIcon"},
        {EnabledRole, "enabled"},
        {SentRole, "sent"},
        {DeclaredRole, "declared"},
    };
}

} // namespace MaiaNotifications
