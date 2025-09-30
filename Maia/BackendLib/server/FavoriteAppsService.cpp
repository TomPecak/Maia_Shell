#include "FavoriteAppsService.hpp"
#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

FavoriteAppsDBus::FavoriteAppsDBus(QObject *parent)
    : QObject(parent)
{
    qDebug() << "[STARTUP INFO] Starting: " << __PRETTY_FUNCTION__;
    FavApplication::registerDBusTypes();

    QDBusConnection sessionBus = QDBusConnection::sessionBus();
    if (!sessionBus.registerService("org.maia.FavoriteApplications")) {
        qDebug("[ERROR] Failed to register D-Bus service: %s", qPrintable(sessionBus.lastError().message()));
    }

    if (!sessionBus.registerObject("/FavoriteApplications",
                                   this,
                                   QDBusConnection::ExportScriptableSlots
                                       | QDBusConnection::ExportScriptableSignals)) {
        qDebug("[ERROR] Failed to register D-Bus object: %s", qPrintable(sessionBus.lastError().message()));
    }
}

FavoriteAppsDBus::~FavoriteAppsDBus() {}

void FavoriteAppsDBus::setFavoritesModel(FavoriteAppsProxyModel *model)
{
    if (m_favoritesModel) {
        disconnect(m_favoritesModel, nullptr, this, nullptr);
    }

    m_favoritesModel = model;

    if (m_favoritesModel) {
        connect(m_favoritesModel,
                &FavoriteAppsProxyModel::favoriteAdded,
                this,
                &FavoriteAppsDBus::_onFavoriteAdded);

        connect(m_favoritesModel,
                &FavoriteAppsProxyModel::favoriteRemoved,
                this,
                &FavoriteAppsDBus::_onFavoriteRemoved);

        connect(m_favoritesModel,
                &FavoriteAppsProxyModel::favoritesChanged,
                this,
                &FavoriteAppsDBus::favoritesChanged);
    }
}

void FavoriteAppsDBus::addFavorite(const QString &appId)
{
    if (m_favoritesModel) {
        m_favoritesModel->addFavorite(appId);
    } else {
        qDebug() << "Favorite model not set in DBus adaptor!";
    }
}

void FavoriteAppsDBus::removeFavorite(const QString &appId)
{
    if (m_favoritesModel) {
        m_favoritesModel->removeFavorite(appId);
    } else {
        qDebug() << "Favorite model not set in DBus adaptor!";
    }
}

QVector<FavApplication> FavoriteAppsDBus::getFavorites()
{
    QVector<FavApplication> favApplications;
    if (!m_favoritesModel) {
        qDebug() << "Favorite model not set in DBus adaptor!";
        return favApplications;
    }

    auto *sourceModel = dynamic_cast<ApplicationModel *>(m_favoritesModel->sourceModel());
    if (!sourceModel) {
        qDebug() << "Invalid source model!";
        return favApplications;
    }

    for (int i = 0; i < m_favoritesModel->rowCount(); ++i) {
        QModelIndex proxyIndex = m_favoritesModel->index(i, 0);
        QString appId = m_favoritesModel->data(proxyIndex, ApplicationModel::IdRole).toString();
        Application appData = sourceModel->getApplicationById(appId);

        if (!appData.id.isEmpty()) {
            FavApplication app{appData.id, appData.name, appData.exec, appData.icon};
            favApplications.append(app);
        }
    }

    return favApplications;
}

void FavoriteAppsDBus::_onFavoriteAdded(const QString &appId)
{
    if (!m_favoritesModel)
        return;

    auto *sourceModel = dynamic_cast<ApplicationModel *>(m_favoritesModel->sourceModel());

    if (!sourceModel)
        return;

    Application appData = sourceModel->getApplicationById(appId);

    if (appData.id.isEmpty())
        return;

    FavApplication favApp{appData.id, appData.name, appData.exec, appData.icon};

    emit favoriteAdded(favApp);
}

void FavoriteAppsDBus::_onFavoriteRemoved(const QString &appId)
{
    if (!m_favoritesModel)
        return;

    auto *sourceModel = dynamic_cast<ApplicationModel *>(m_favoritesModel->sourceModel());

    if (!sourceModel)
        return;

    Application appData = sourceModel->getApplicationById(appId);

    if (appData.id.isEmpty())
        return;

    FavApplication favApp{appData.id, appData.name, appData.exec, appData.icon};

    emit favoriteRemoved(favApp);
}

FavoriteAppsService::FavoriteAppsService(QObject *parent, QAbstractItemModel *sourceModel)
    : QObject(parent)
    , m_favoriteAppsDBus(this)
{
    m_favoriteAppsModel.setSourceModel(sourceModel);
    m_favoriteAppsDBus.setFavoritesModel(&m_favoriteAppsModel);
}

FavoriteAppsService::~FavoriteAppsService() {}
