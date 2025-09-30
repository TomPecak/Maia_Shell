#pragma once

#include <QObject>
#include <QQmlApplicationEngine>

#include "../AppsListModel.hpp"
#include "../MAudioBackend.hpp"
#include "../Backend.hpp"
#include "../BackendAppsIconsProvider.hpp"
#include "../TaskbarIconProvider.hpp"
#include "FavoriteAppsListModel.hpp"

class QmlGui : public QObject
{
    Q_OBJECT
public:
    explicit QmlGui(QObject *parent = nullptr,
                    QGuiApplication *app = nullptr,
                    int swapIntervalOption = 0);

    void initQmlEngine();

    void deleteQmlEngineRootObjects();
    void loadFromModule(QAnyStringView uri, QAnyStringView typeName);
    void load(const QString &filePath);

private:
    QGuiApplication *m_app = nullptr;
    int m_swapIntervalOption = 0;

    QQmlApplicationEngine engine;
    Backend backend;
    BackendAppsIconsProvider appsIconProvider;
    TaskbarIconsProvider taskbarIconProvider;
    ApplicationModel appsListModel;
    FilterProxyModel filterProxyModel;
    MAudioBackend audioBackend;
};
