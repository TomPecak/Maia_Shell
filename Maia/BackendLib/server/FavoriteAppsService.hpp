#pragma once

#include <QAbstractItemModel>
#include <QDBusAbstractAdaptor>
#include <QObject>
#include <QVector>

#include "Application.hpp"
#include "FavoriteAppsListModel.hpp"

class FavoriteAppsDBus : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.maia.FavoriteApplications")

public:
    explicit FavoriteAppsDBus(QObject *parent = nullptr);
    ~FavoriteAppsDBus();

    void setFavoritesModel(FavoriteAppsProxyModel *model);

signals:
    //D-bus API
    Q_SCRIPTABLE void favoriteAdded(const FavApplication &app);
    Q_SCRIPTABLE void favoriteRemoved(const FavApplication &app);
    Q_SCRIPTABLE void favoritesChanged();

public slots:
    //D-bus API
    Q_SCRIPTABLE Q_NOREPLY void addFavorite(const QString &appId);
    Q_SCRIPTABLE Q_NOREPLY void removeFavorite(const QString &appId);
    Q_SCRIPTABLE QVector<FavApplication> getFavorites();

private slots:
    // Private slots for handling signals from the model
    void _onFavoriteAdded(const QString &appId);
    void _onFavoriteRemoved(const QString &appId);

private:
    FavoriteAppsProxyModel *m_favoritesModel = nullptr;
};

class FavoriteAppsService : public QObject
{
    Q_OBJECT
public:
    explicit FavoriteAppsService(QObject *parent = nullptr,
                                 QAbstractItemModel *sourceModel = nullptr);
    ~FavoriteAppsService();

private:
    FavoriteAppsDBus m_favoriteAppsDBus;
    FavoriteAppsProxyModel m_favoriteAppsModel;
};
