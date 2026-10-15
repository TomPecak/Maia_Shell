#include "FrontendLoader.hpp"

#include <QDBusConnectionInterface>
#include <QScxmlStateMachine>

#include "GuiManagerStateMachine.h"

static bool verifyRunningUnderKwinWayland();

FrontendLoader::FrontendLoader(QObject *parent, QGuiApplication *app, int swapIntervalOption)
    : QObject(parent)
    , m_x11WindowManagerService(this)
    , m_qmlGui(this, app, swapIntervalOption)
    , changeFrontendStateMachine(new GuiManagerStateMachine(this))
{
    HOME_ENV = QString::fromUtf8(qgetenv("HOME"));
}

FrontendLoader::~FrontendLoader()
{
    qDebug() << __PRETTY_FUNCTION__;
}

void FrontendLoader::startGui(const FrontendInfo &frontend)
{
    qDebug() << "[STARTUP INFO] " << __PRETTY_FUNCTION__ << " frontend.name=" << frontend.name;
    //Maia does not start KWin, kwin_wayland starts Maia, check that we are really running under it
    verifyRunningUnderKwinWayland();

    m_qmlGui.initQmlEngine();
    m_currentFrontend = frontend;

    connect(&m_x11WindowManagerService,
            &WindowManagerX11Service::reconfigureFinished,
            this,
            &FrontendLoader::handleKwinReconfigured);

    changeFrontendStateMachine->start();

    changeFrontendStateMachine->connectToState(QStringLiteral("DeletingQmlObjects"), [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "DeletingQmlObjects";
            m_qmlGui.deleteQmlEngineRootObjects();
            Q_EMIT frontendUnloaded();
            changeFrontendStateMachine->submitEvent(QStringLiteral("qmlObjectsDeleted"));
        } else {
            qDebug() << "Exit state: " << "DeletingQmlObjects";
        }
    });

    changeFrontendStateMachine->connectToState(QStringLiteral("ReconfiguringWindowManager"), [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "ReconfiguringWindowManager";
            m_x11WindowManagerService.reconfigure();
        } else {
            qDebug() << "Exit state: " << "ReconfiguringWindowManager";
        }
    });

    //We need to reconfigure kwin after loading the QML frontend,
    //among other reasons, because QML modules control kwin window decorations.
    //Changing the window decorations involves opening the kwin
    //configuration file 'kwinrc' and modifying its contents.
    //For this change to take effect, kwin needs to be reloaded.

    changeFrontendStateMachine->connectToState(QStringLiteral("ReconfigureWindowManagerAfterLoading"),
                                              [=](bool active) {
                                                  if (active) {
                                                      qDebug()
                                                          << "Enter state: "
                                                          << "ReconfigureWindowManagerAfterLoading";
                                                      m_x11WindowManagerService.reconfigure();
                                                  } else {
                                                      qDebug()
                                                          << "Exit state: "
                                                          << "ReconfigureWindowManagerAfterLoading";
                                                  }
                                              });

    changeFrontendStateMachine->connectToState(QStringLiteral("EmittingFrontendChanged"), [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "EmittingFrontendChanged";

            qDebug() << "Server 9 " << __PRETTY_FUNCTION__ << " Q_EMIT frontendChanged()";
            Q_EMIT frontendChanged(m_currentFrontend.id);

            changeFrontendStateMachine->submitEvent(QStringLiteral("frontendChangedEmitted"));
        } else {
            qDebug() << "Exit state: " << "EmittingFrontendChanged";
        }
    });

    changeFrontendStateMachine->connectToState(QStringLiteral("LoadingFrontend"), [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "LoadingFrontend";

            loadFrontend();

            changeFrontendStateMachine->submitEvent(QStringLiteral("frontendLoaded"));
        } else {
            qDebug() << "Exit state: " << "LoadingFrontend";
        }
    });

    changeFrontendStateMachine->connectToState(QStringLiteral("WaitAfterLoaded"), [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "WaitAfterLoaded";
            QTimer::singleShot(10000, [=]() {
                changeFrontendStateMachine->submitEvent(QStringLiteral("waitingLoadDelayEnded"));
            });

        } else {
            qDebug() << "Exit state: " << "WaitAfterLoaded";
        }
    });

    //START QML GUI, submit event that kik off state machine form idle to running state
    qDebug() << "[STARTUP INFO] changeFrontendStateMachine->submitEvent('initialStart')";
    changeFrontendStateMachine->submitEvent(QStringLiteral("initialStart"));
}

void FrontendLoader::tryLoadFrontend(const FrontendInfo &frontend)
{
    m_currentFrontend = frontend;
    changeFrontendStateMachine->submitEvent(QStringLiteral("startFrontendChange"));
}

void FrontendLoader::uninit()
{
    m_qmlGui.deleteQmlEngineRootObjects();
}

void FrontendLoader::handleKwinReconfigured()
{
    qDebug() << __PRETTY_FUNCTION__ << changeFrontendStateMachine->activeStateNames();
    if (changeFrontendStateMachine->isActive(QStringLiteral("ReconfiguringWindowManager"))) {
        qDebug() << "changeFrontendStateMachine->submitEvent(windowManagerReconfigured);";
        changeFrontendStateMachine->submitEvent(QStringLiteral("windowManagerReconfigured"));
    } else if (changeFrontendStateMachine->isActive(QStringLiteral("ReconfigureWindowManagerAfterLoading"))) {
        qDebug() << "changeFrontendStateMachine->submitEvent(reconfigured);";
        changeFrontendStateMachine->submitEvent(QStringLiteral("reconfigured"));
    }
}

void FrontendLoader::loadFrontend()
{
    qDebug() << "[ INFO ] " << __PRETTY_FUNCTION__;
    qDebug() << "[ INFO ] Current frontend name = " << m_currentFrontend.name;
    qDebug() << "[ INFO ] Current frontend qmlFilePath = " << m_currentFrontend.qmlFilePath;
    if (m_currentFrontend.qmlFilePath != QStringLiteral("")) {
        m_qmlGui.load(m_currentFrontend.qmlFilePath);
    } else if (m_currentFrontend.qmlUri != QStringLiteral("")) {
        m_qmlGui.loadFromModule(m_currentFrontend.qmlUri, m_currentFrontend.qmlTypeName);
    }
}

bool verifyRunningUnderKwinWayland()
{
    // Since the X11 session was dropped, Maia no longer starts the window manager.
    // Maia is started by kwin_wayland (--exit-with-session in run_maia_wayland.sh
    // or run_maia_nested_wayland.sh), so KWin must already be running at this point.
    // Maia runs as a native Wayland client (-platform wayland), WAYLAND_DISPLAY
    // is inherited from kwin_wayland.
    bool ok = true;

    if (qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY")) {
        qDebug() << "[STARTUP ERROR] WAYLAND_DISPLAY is not set. Maia must be started by kwin_wayland "
                    "(run_maia_wayland.sh or run_maia_nested_wayland.sh).";
        ok = false;
    }

    QDBusConnectionInterface *busInterface = QDBusConnection::sessionBus().interface();
    if (!busInterface || !busInterface->isServiceRegistered(QStringLiteral("org.kde.KWin"))) {
        qDebug() << "[STARTUP ERROR] KWin D-Bus service 'org.kde.KWin' is not registered on the session bus. "
                    "Window manager reconfiguration and KWin effects will not work.";
        ok = false;
    }

    if (ok) {
        qDebug() << "[STARTUP INFO] Running under kwin_wayland, WAYLAND_DISPLAY="
                 << qgetenv("WAYLAND_DISPLAY") << " platform=" << QGuiApplication::platformName();
    }

    return ok;
}
