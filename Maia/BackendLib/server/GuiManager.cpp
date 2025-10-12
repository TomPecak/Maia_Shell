#include "GuiManager.hpp"

#include <QDBusConnectionInterface>
#include <QDBusServiceWatcher>

#include "../maia_version.h"
#include "../helper/Process.hpp"

static bool startKwinAndWaitForReady(QProcess &process, int timeoutMs = 15000);

GuiManager::GuiManager(QObject *parent, QGuiApplication *app, int swapIntervalOption)
    : QObject(parent)
    , m_x11WindowManagerService(this)
    , m_qmlGui(this, app, swapIntervalOption)
    , changeFrontendStateMachine(this)
{
    HOME_ENV = qgetenv("HOME");

    connect(&m_kwin, &QProcess::readyReadStandardOutput, [&]() {
        qDebug() << "[INFO KWIN] " << m_kwin.readAllStandardOutput();
    });

    connect(&m_kwin, &QProcess::readyReadStandardError, [&]() {
        qDebug() << "[ERROR KWIN] " << m_kwin.readAllStandardError();
    });
}

GuiManager::~GuiManager()
{
    qDebug() << __PRETTY_FUNCTION__;
}

void GuiManager::startGui(const FrontendInfo &frontend)
{
    qDebug() << "[STARTUP INFO] " << __PRETTY_FUNCTION__ << " frontend.name=" << frontend.name;
    //START KWIN
    startKwinAndWaitForReady(m_kwin);

    m_qmlGui.initQmlEngine();
    m_currentFrontend = frontend;

    connect(&m_x11WindowManagerService,
            &WindowManagerX11Service::reconfigureFinished,
            this,
            &GuiManager::handleKwinReconfigured);

    changeFrontendStateMachine.start();

    changeFrontendStateMachine.connectToState("DeletingQmlObjects", [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "DeletingQmlObjects";
            m_qmlGui.deleteQmlEngineRootObjects();
            emit frontendUnloaded();
            changeFrontendStateMachine.submitEvent("qmlObjectsDeleted");
        } else {
            qDebug() << "Exit state: " << "DeletingQmlObjects";
        }
    });

    changeFrontendStateMachine.connectToState("ReconfiguringWindowManager", [=](bool active) {
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

    changeFrontendStateMachine.connectToState("ReconfigureWindowManagerAfterLoading",
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

    changeFrontendStateMachine.connectToState("EmittingFrontendChanged", [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "EmittingFrontendChanged";

            qDebug() << "Server 9 " << __PRETTY_FUNCTION__ << " emit frontendChanged()";
            emit frontendChanged(m_currentFrontend.id);

            changeFrontendStateMachine.submitEvent("frontendChangedEmitted");
        } else {
            qDebug() << "Exit state: " << "EmittingFrontendChanged";
        }
    });

    changeFrontendStateMachine.connectToState("LoadingFrontend", [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "LoadingFrontend";

            loadFrontend();

            changeFrontendStateMachine.submitEvent("frontendLoaded");
        } else {
            qDebug() << "Exit state: " << "LoadingFrontend";
        }
    });

    changeFrontendStateMachine.connectToState("WaitAfterLoaded", [=](bool active) {
        if (active) {
            qDebug() << "Enter state: " << "WaitAfterLoaded";
            QTimer::singleShot(10000, [=]() {
                changeFrontendStateMachine.submitEvent("waitingLoadDelayEnded");
            });

        } else {
            qDebug() << "Exit state: " << "WaitAfterLoaded";
        }
    });

    //START QML GUI, submit event that kik off state machine form idle to running state
    qDebug() << "[STARTUP INFO] changeFrontendStateMachine.submitEvent('initialStart')";
    changeFrontendStateMachine.submitEvent("initialStart");
}

void GuiManager::tryLoadFrontend(const FrontendInfo &frontend)
{
    m_currentFrontend = frontend;
    changeFrontendStateMachine.submitEvent("startFrontendChange");
}

void GuiManager::uninit()
{
    m_qmlGui.deleteQmlEngineRootObjects();

    if (m_kwin.state() != QProcess::NotRunning) {
        m_kwin.terminate();
        m_kwin.waitForFinished();
    }
}

void GuiManager::handleKwinReconfigured()
{
    qDebug() << __PRETTY_FUNCTION__ << changeFrontendStateMachine.activeStateNames();
    if (changeFrontendStateMachine.isActive("ReconfiguringWindowManager")) {
        qDebug() << "changeFrontendStateMachine.submitEvent(windowManagerReconfigured);";
        changeFrontendStateMachine.submitEvent("windowManagerReconfigured");
    } else if (changeFrontendStateMachine.isActive("ReconfigureWindowManagerAfterLoading")) {
        qDebug() << "changeFrontendStateMachine.submitEvent(reconfigured);";
        changeFrontendStateMachine.submitEvent("reconfigured");
    }
}

void GuiManager::loadFrontend()
{
    qDebug() << "[INFO] " << __PRETTY_FUNCTION__;
    if (m_currentFrontend.qmlFilePath != "") {
        m_qmlGui.load(m_currentFrontend.qmlFilePath);
    } else if (m_currentFrontend.qmlUri != "") {
        m_qmlGui.loadFromModule(m_currentFrontend.qmlUri, m_currentFrontend.qmlTypeName);
    }
}

bool startKwinAndWaitForReady(QProcess &process, int timeoutMs)
{
#warning "This code should be modified; it should be handled in a state machine."

    // Check if KWin is already running
    QDBusConnection sessionBus = QDBusConnection::sessionBus();
    if (sessionBus.interface()->isServiceRegistered("org.kde.KWin")) {
        qDebug() << "[ERROR] KWin is already running, not starting a new process.";
        return true;
    }

    qDebug() << "Starting kwin process...";

    //Create and start a timer to measure time
    QElapsedTimer startupTimer;
    startupTimer.start();

    // Set the environment as before
    // Why do we filter environment variables? Let's assume Maia is compiled with different libraries than KWin in the target system.
    // If LD_LIBRARY_PATH points to Maia's library path, KWin will link to Maia's libraries instead of the system libraries.
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    QString homePath = qgetenv("HOME");

    filterProcessEnvironment(env, QString("/opt/Maia/Maia_") + QString(MAIA_VERSION_STRING) + QString("/lib"));
    process.setProcessEnvironment(env);

    // Start the process
    process.start("kwin_x11"); // or "kwin_wayland" depending on the session

    if (!process.waitForStarted(5000)) {
        qDebug() << "[ERROR] Failed to start kwin process! Error:" << process.errorString();
        return false;
    }

    qDebug() << "[STARTUP INFO] KWin process started. Waiting for D-Bus service registration "
                "'org.kde.KWin'...";

    // Use QDBusServiceWatcher to wait for readiness
    QDBusServiceWatcher watcher("org.kde.KWin",
                                sessionBus,
                                QDBusServiceWatcher::WatchForRegistration);

    // Create an event loop to wait for the signal without blocking everything
    QEventLoop loop;

    // Connect the service registration signal to exit the event loop
    QObject::connect(&watcher, &QDBusServiceWatcher::serviceRegistered, &loop, &QEventLoop::quit);

    // Set a timeout to avoid waiting indefinitely
    QTimer timeoutTimer; // Renamed for clarity
    timeoutTimer.setSingleShot(true);
    QObject::connect(&timeoutTimer, &QTimer::timeout, &loop, &QEventLoop::quit);
    timeoutTimer.start(timeoutMs);

    // Run the event loop. It will exit when the service registers or the timeout expires.
    loop.exec();

    // Check why we exited the loop
    if (timeoutTimer.isActive()) {
        // Timer is still active, meaning the watcher's signal ended the loop
        timeoutTimer.stop();

        // Get and display the elapsed time
        qint64 elapsedMs = startupTimer.elapsed();
        qDebug().nospace() << "[STARTUP INFO] KWin is ready (D-Bus service registered). "
                              "Startup took: "
                           << elapsedMs << " ms.";

        return true;
    } else {
        // Timer expired
        qDebug() << "[STARTUP ERROR] Timeout! KWin did not register its D-Bus service within "
                 << timeoutMs << "ms.";
process.terminate(); // Terminate the process, which likely hung
        process.waitForFinished(1000);
        return false;
    }
}
