#pragma once

#include <QGuiApplication>
#include <QObject>
#include <QQmlApplicationEngine>

#include "FavoriteAppsService.hpp"
#include "FrontendManagerService.hpp"
#include "GuiManager.hpp"
#include "SessionService.hpp"

class Server : public QObject
{
    Q_OBJECT
public:
    explicit Server(QGuiApplication *app = nullptr, int swapInterval = 0);
    ~Server();

    //d-bus request from client
    void handleFrontendChangeRequest(const QString &themeId);
    void handleFrontendChangeRequest(const FrontendInfo & forntend);

private slots:
    void sessionLogout();
    void handleGuiManagerFrontendChanged(const QString &themeId);

private:
    SessionService m_sessionService;
    FrontendManagerService m_frontendManagerService;

    DesktopApplicationModel m_applicationModel;
    FavoriteAppsService m_favoriteAppsService;

    GuiManager m_guiManager;
};
