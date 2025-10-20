#pragma once

#include <QFuture>
#include <QSettings>
#include <QSortFilterProxyModel>
#include <QtConcurrent>
#include "../AppsListModel.hpp"

class FavoriteAppsProxyModel : public QSortFilterProxyModel
{
    Q_OBJECT
public:
    explicit FavoriteAppsProxyModel(QObject *parent = nullptr)
        : QSortFilterProxyModel(parent)
    {
        loadFavoritesAsync();
    }

    Q_INVOKABLE void addFavorite(const QString &appId)
    {
        if (!favoriteAppsIds.contains(appId)) {
            favoriteAppsIds.append(appId);
            saveFavoritesAsync();
            invalidateFilter();

            emit favoriteAdded(appId);
            emit favoritesChanged();
        }
    }

    Q_INVOKABLE void removeFavorite(const QString &appId)
    {
        if (favoriteAppsIds.contains(appId)) {
            favoriteAppsIds.removeAll(appId);
            saveFavoritesAsync();
            invalidateFilter();
            emit favoriteRemoved(appId);
            emit favoritesChanged();
        }
    }

    Q_INVOKABLE bool isFavorite(const QString &appId) const
    {
        return favoriteAppsIds.contains(appId);
    }

signals:
    void favoritesChanged();
    void favoriteAdded(const QString &appId);
    void favoriteRemoved(const QString &appId);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override
    {
        QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);
        QString appId = index.data(DesktopApplicationModel::IdRole).toString();
        return isFavorite(appId);
    }

private:
    QStringList favoriteAppsIds;

    void loadFavoritesAsync()
    {
        QFuture<QStringList> future = QtConcurrent::run([] {
            QSettings settings;
            return settings.value("FavoriteAppsList", QStringList()).toStringList();
        });

        QFutureWatcher<QStringList> *watcher = new QFutureWatcher<QStringList>(this);
        connect(watcher, &QFutureWatcher<QStringList>::finished, this, [this, watcher]() {
            favoriteAppsIds = watcher->result();
            watcher->deleteLater();

            invalidateFilter();
            emit favoritesChanged();
        });
        watcher->setFuture(future);
    }

    void saveFavoritesAsync()
    {
        QStringList copy = favoriteAppsIds;
        [[maybe_unused]] auto future = QtConcurrent::run([copy]() {
            QSettings settings;
            settings.setValue("FavoriteAppsList", copy);
        });
    }
};
