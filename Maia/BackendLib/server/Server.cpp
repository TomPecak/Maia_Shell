#include "Server.hpp"

#include <QDebug>
#include <QQuickWindow>

Server::Server(QGuiApplication *app, int swapIntervalOption)
    : QObject(app)
    , m_sessionService(this)
    , m_applicationModel(this)
    , m_favoriteAppsService(this, &m_applicationModel)
    , m_frontendManagerService(this)
    , m_guiManager(this, app, swapIntervalOption)

{
    qDebug() << __PRETTY_FUNCTION__;

    connect(&m_sessionService, &SessionService::logoutRequest, this, &Server::sessionLogout);

    connect(&m_frontendManagerService,
            qOverload<const QString & >(&FrontendManagerService::activeFrontendChangeRequest),
            this,
            qOverload<const QString & >(&Server::handleFrontendChangeRequest));

    connect(&m_frontendManagerService,
            qOverload<const FrontendInfo & >(&FrontendManagerService::activeFrontendChangeRequest),
            this,
            qOverload<const FrontendInfo & >(&Server::handleFrontendChangeRequest));

    connect(&m_guiManager,
            &GuiManager::frontendChanged,
            this,
            &Server::handleGuiManagerFrontendChanged);


    m_guiManager.startGui(m_frontendManagerService.getCurrentFrontent());
}

Server::~Server()
{
    qDebug() << __PRETTY_FUNCTION__;
}

void Server::handleFrontendChangeRequest(const QString &themeId)
{

}

void Server::handleFrontendChangeRequest(const FrontendInfo &forntend)
{
    m_guiManager.tryLoadFrontend(forntend);
}


void Server::sessionLogout()
{
    m_guiManager.uninit();
    QCoreApplication::exit(0);
}

void Server::handleGuiManagerFrontendChanged(const QString &frontendId)
{
    m_frontendManagerService.activeFrontendChangeConfirmation(frontendId);
}
