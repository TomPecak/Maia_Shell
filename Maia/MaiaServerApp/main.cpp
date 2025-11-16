#include <csignal>
#include <memory>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QGuiApplication>
#include <QObject>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>
#include <QWindow>
#include <QtQuick3D/qquick3d.h>
#include <QtWebEngineQuick>

#include <AppsListModel.hpp>
#include <MAudioBackend.hpp>
#include <MSessionManager.hpp>
#include <Backend.hpp>
#include <BackendAppsIconsProvider.hpp>
#include <TaskbarIconProvider.hpp>
#include <helper/Process.hpp>
#include <private/ProxyWindowServer.hpp>
#include <server/Server.hpp>
#include <iconthemeprovider.hpp>

#include <cmake_config.h>

#include "maia_version.h"

#include "logger.hpp"

// #include <QtQml/QQmlExtensionPlugin>
// Q_IMPORT_QML_PLUGIN(XPFrontendPlugin)

void getCmdLineOptions(const QCoreApplication &app,
                       QString &modeOption,
                       QString &sourceOption,
                       int &x,
                       int &y,
                       int &width,
                       int &height,
                       int &swapInterval,
                       QString &proxyWindowAddress,
                       bool &proxyVisibleOption);

static void signalHandler(int signal)
{
    //use exit instead quit, exit always work ok, quit not always
    //QCoreApplication::quit();
    QCoreApplication::exit();
}

void setWindowGeometry(
    QQmlApplicationEngine &engine, int x, int y, int width, int height, bool visible);

int main(int argc, char *argv[])
{
    // Rejestracja obsługi sygnałów systemowych
    std::signal(SIGTERM, signalHandler); // Sygnał zakończenia (np. z Qt Creatora lub kill)
    std::signal(SIGINT, signalHandler);  // Ctrl+C w terminalu

    //READ ENVIROMENT VARIABLES
    QString homePath = qgetenv("HOME");

    //INIT APPLICATION
    QGuiApplication::setApplicationName(QString("Maia_") + MAIA_VERSION_STRING);
    QGuiApplication::setOrganizationName("Maia");
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);

    Logger logger;
    logger.run();
    qDebug() << "FIRST LOG ??????????????????????????";

    //INIT APPLICATION OPTIONS
    QString modeOption, sourceOption, proxyWinAddress;
    int xOption, yOption, widthOption, heightOption, swapInterwalOption;
    bool proxyVisibleOption;

    getCmdLineOptions(app,
                      modeOption,
                      sourceOption,
                      xOption,
                      yOption,
                      widthOption,
                      heightOption,
                      swapInterwalOption,
                      proxyWinAddress,
                      proxyVisibleOption);

    qDebug() << "[STARTUP INFO] " << "Proxy Window Address: " << proxyWinAddress;

    if (modeOption == "server") {
        //SERVER

        qDebug() << "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH UJ 333333333 !!!";

        Server server(&app, swapInterwalOption);

        qDebug() << "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH UJ !!!";

        int retValue = app.exec();

        qDebug() << "SERVER EXIT SUCESSFULL with retValue=" << retValue;
        return retValue;

    } else {
        //QML PROXY WINDOW

        qDebug() << "[INFO] INIT QML PROXY WINDOW PROCESS ---------------------------";

        //INIT SURFACE
        QSurfaceFormat surfaceFormat = QQuick3D::idealSurfaceFormat();
        //QSurfaceFormat surfaceFormat = QSurfaceFormat::defaultFormat();
        surfaceFormat.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
        surfaceFormat.setSwapInterval(swapInterwalOption);
        QSurfaceFormat::setDefaultFormat(surfaceFormat);

        QQmlApplicationEngine engine;


        // QString runType = qgetenv("MAIA_QTCREATOR_RUN");
        // QString gnomeModulePath;
        // QString cutefishModulePath;
        // QString xplunaModulePath;
        // if(runType == "1"){ //Maia is running form QtCreator (dev run)
        //     QString cmake_deploy_prefix = QString::fromStdString(std::string(CMAKE_INSTALL_PREFIX));
        //     gnomeModulePath = cmake_deploy_prefix + QString("/frontends/Gnome/");
        //     cutefishModulePath = cmake_deploy_prefix + QString("/frontends/Cutefish/");
        //     xplunaModulePath = cmake_deploy_prefix + QString("/frontends/XPLuna/");
        // }else{  //normal Maia run, form login manager (SDDM, GDM, etc)
        //     gnomeModulePath = QString("/opt/Maia/Maia_") + QString(MAIA_VERSION_STRING) + "/frontends/Gnome/";
        //     cutefishModulePath = QString("/opt/Maia/Maia_") + QString(MAIA_VERSION_STRING) + "/frontends/Cutefish/";
        //     xplunaModulePath = QString("/opt/Maia/Maia_") + QString(MAIA_VERSION_STRING) + "/frontends/XPLuna/";
        // }
        // engine.addImportPath(gnomeModulePath);
        // engine.addImportPath(cutefishModulePath);
        // engine.addImportPath(xplunaModulePath);
        // qDebug() << "[INFO] engine.addImportPath(gnomeModulePath) = " << gnomeModulePath;
        // qDebug() << "[INFO] engine.addImportPath(cutefishModulePath) = " << cutefishModulePath;
        // qDebug() << "[INFO] engine.addImportPath(xplunaModulePath) = " << xplunaModulePath;


        Backend backend(homePath);

        //INIT QML ENGINE ICON PROVIDERS
        BackendAppsIconsProvider appsIconProvider;
        engine.addImageProvider(QLatin1String("backend_app_icon"), &appsIconProvider);
        engine.addImageProvider(QLatin1String("backendTaskbarIcons"), new TaskbarIconsProvider);
        engine.addImageProvider(QStringLiteral("icontheme"), new IconThemeProvider());

        //INIT QML ENGINE CONTEXT PROPERTIES
        DesktopApplicationModel appsListModel;
        FilterProxyModel filterProxyModel;
        filterProxyModel.setSourceModel(&appsListModel);

        ProxyWindowLocalServer server;
        if (!server.startServer(proxyWinAddress)) {
            return -1;
        }

        engine.rootContext()->setContextProperty("HOME", homePath);
        //Apps List models
        engine.rootContext()->setContextProperty("appsListModel", &filterProxyModel);

        engine.rootContext()->setContextProperty("backend", &backend);

        //Audio backend
        MAudioBackend audioBackend;
        engine.rootContext()->setContextProperty("audioBackend", &audioBackend);

        QObject::connect(
            &engine,
            &QQmlApplicationEngine::objectCreationFailed,
            &app,
            []() {
                qDebug() << "QCoreApplication::exit(-1); 3";
                QCoreApplication::exit(-1);
            },
            Qt::QueuedConnection);

        engine.load(QUrl(sourceOption));

        //Make sure the main QML object is loaded.
        if (engine.rootObjects().isEmpty())
            return -1;

        setWindowGeometry(engine, xOption, yOption, widthOption, heightOption, proxyVisibleOption);
        server.installWindow(engine);

        auto retValue = app.exec();

        qDebug() << "PROXY CLIENT EXIT SUCESSFULL with retValue=" << retValue;
        logger.uninit();
        return retValue;
    }
}

void getCmdLineOptions(const QCoreApplication &app,
                       QString &modeOption,
                       QString &sourceOption,
                       int &x,
                       int &y,
                       int &width,
                       int &height,
                       int &swapInterval,
                       QString &proxyWindowAddress,
                       bool &proxyVisible)
{
    QCommandLineParser parser;
    parser.setApplicationDescription("Command-line options parser for the application");
    parser.addHelpOption();
    parser.addVersionOption();

    // Define command-line options
    QCommandLineOption modeOpt("mode", "Set application mode (server/client)", "value", "server");
    QCommandLineOption sourceOpt("source", "Set QML source URL (e.g., qrc:///Clock3D.qml)", "value");
    QCommandLineOption xOpt("x", "Set window X position", "x", "100");
    QCommandLineOption yOpt("y", "Set window Y position", "y", "100");
    QCommandLineOption widthOpt("width", "Set window width", "width", "800");
    QCommandLineOption heightOpt("height", "Set window height", "height", "600");
    QCommandLineOption swapIntervalOpt("swap-interval", "Set swap interval", "value", "1");
    QCommandLineOption proxyWinAddressOpt("proxy-window-addr",
                                          "Set proxy window local socket address",
                                          "value",
                                          "/tmp/maia-XYZ");
    QCommandLineOption proxyVisibleOpt("proxy-visible",
                                       "Set proxy window visibility (true/false)",
                                       "value",
                                       "false");

    // Add options to parser
    parser.addOptions({modeOpt,
                       sourceOpt,
                       xOpt,
                       yOpt,
                       widthOpt,
                       heightOpt,
                       swapIntervalOpt,
                       proxyWinAddressOpt,
                       proxyVisibleOpt}); // Dodaj proxyVisibleOpt

    // Process arguments
    parser.process(app);

    // Set default values
    modeOption = parser.value(modeOpt);
    sourceOption = parser.value(sourceOpt);
    proxyWindowAddress = parser.value(proxyWinAddressOpt);
    x = 100;
    y = 100;
    width = 800;
    height = 600;
    swapInterval = 0;
    proxyVisible = false;

    // Parse mode option
    if (parser.isSet(modeOpt)) {
        QString value = parser.value(modeOpt).toLower();
        if (value == "server" || value == "client") {
            modeOption = value;
        } else {
            qDebug() << "Invalid --mode value:" << value << "(expected: server or client)";
        }
    }

    // Parse source option
    if (parser.isSet(sourceOpt)) {
        qDebug() << "Source set to:" << sourceOption;
    }

    // Parse proxy-visible option
    if (parser.isSet(proxyVisibleOpt)) {
        QString value = parser.value(proxyVisibleOpt).toLower();
        if (value == "true") {
            proxyVisible = true;
        } else if (value == "false") {
            proxyVisible = false;
        } else {
            qDebug() << "Invalid --proxy-visible value:" << value << "(expected: true or false)";
        }
    }

    // Parse geometry options with validation
    auto parseIntOption = [&parser](const QCommandLineOption &opt, int &target, const char *name) {
        if (parser.isSet(opt)) {
            bool ok;
            int value = parser.value(opt).toInt(&ok);
            if (ok && value >= 0) {
                target = value;
            } else {
                qDebug() << "Invalid" << name << "value:" << parser.value(opt)
                << "(expected: non-negative integer)";
            }
        }
    };

    parseIntOption(xOpt, x, "--x");
    parseIntOption(yOpt, y, "--y");
    parseIntOption(widthOpt, width, "--width");
    parseIntOption(heightOpt, height, "--height");
    parseIntOption(swapIntervalOpt, swapInterval, "--swap-interval");
}

void setWindowGeometry(
    QQmlApplicationEngine &engine, int x, int y, int width, int height, bool visible)
{
    if (engine.rootObjects().isEmpty()) {
        qDebug() << "No root objects available to set geometry.";
    }

    QObject *rootObject = engine.rootObjects().first();
    QQuickWindow *window = qobject_cast<QQuickWindow *>(rootObject);

    if (!window) {
        qDebug() << "Root object is not a QQuickWindow!";
    }

    window->setGeometry(x, y, width, height);

    if (visible) {
        window->show();
    } else {
        window->hide();
    }

    qDebug() << "Ustawiono geometrię okna: x=" << x << ", y=" << y << ", width=" << width
             << ", height=" << height;
}

#include "main.moc"
