#pragma once

#include <QAbstractListModel>
#include <QDBusInterface>
#include <qqml.h>

#include "server/Application.hpp"

class MFavoritesAppsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

public:
    enum ApplicationRoles { NameRole = Qt::UserRole + 1, ExecRole, IconRole, IdRole };

    explicit MFavoritesAppsModel(QObject *parent = nullptr);
    ~MFavoritesAppsModel();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void addFavorite(const QString &appId);
    Q_INVOKABLE void removeFavorite(const QString &appId);

private slots:
    void handleFavoriteAdded(const FavApplication &favApp);
    void handleFavoriteRemoved(const FavApplication &favApp);
    //void handleFavoritesChanged();
    void handleGetFavoritesReply(QDBusPendingCallWatcher *watcher);

private:
    QList<FavApplication> favApps;
    QDBusInterface *m_dbusInterface;
};
