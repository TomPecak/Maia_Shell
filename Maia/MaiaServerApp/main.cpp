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
#include <QtPlugin>

#include <AppsListModel.hpp>
#include <MAudioBackend.hpp>
#include <MSessionManager.hpp>
#include <Backend.hpp>
#include <BackendAppsIconsProvider.hpp>
#include <TaskbarIconProvider.hpp>
#include <helper/Process.hpp>
#include <private/ProxyWindowServer.hpp>
#include <server/FrontendModules.hpp>
#include <server/Server.hpp>

#include <QtQml/qqmlextensionplugin.h>

#include <cutefish/fishui/iconthemeprovider.hpp>

#include <cmake_config.h>

#include "maia_version.h"

#include "logger.hpp"

//Maia Client Lib
#include <MLocaleSettings.hpp>

#include <QtQml/QQmlExtensionPlugin>
// Q_IMPORT_QML_PLUGIN(XPFrontendPlugin)

Q_IMPORT_QML_PLUGIN(Maia_BackendPlugin) // URI, '.' dots replaced with '_'

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
    QString homePath = QString::fromUtf8(qgetenv("HOME"));

    // NA RAZIE WYŁĄCZONE: prostszy sterownik animacji Qt Quick.
    // Gdy proces ma więcej niż jedno okno (np. Lumen: pulpit, pasek zadań, flyouty), animacje
    // QML (NumberAnimation, Behavior) nie są zsynchronizowane z klatkami ekranu: zegar animacji
    // tyka co ~16 ms (62,5 Hz), ekran odświeża się 60 Hz i co ~0,4 s animacja przeskakuje
    // o podwójny krok (zmierzone we frontendzie Experimental). Ten sterownik liczy postęp
    // animacji z rzeczywistego czasu przy każdej klatce, co usuwa te przeskoki.
    // Na razie problem omijamy: jedno animowane okno na proces (MProxyWindow) i Animatory
    // (OpacityAnimator, XAnimator...) w Lumen, które działają w wątku renderowania.
    // Musi być ustawione przed utworzeniem QGuiApplication; procesy klientów MProxyWindow
    // dziedziczą środowisko. Nie nadpisujemy wartości ustawionej przez użytkownika.
    // if (!qEnvironmentVariableIsSet("QSG_USE_SIMPLE_ANIMATION_DRIVER"))
    //     qputenv("QSG_USE_SIMPLE_ANIMATION_DRIVER", "1");

    //INIT APPLICATION
    QGuiApplication::setApplicationName(QStringLiteral("Maia_%1").arg(QStringLiteral(MAIA_VERSION_STRING)));
    QGuiApplication::setOrganizationName(QStringLiteral("Maia"));
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);

    volatile auto registrationHack = [](){ MLocaleSettings s; };

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

    if (modeOption == QStringLiteral("server")) {
        //SERVER

        Server server(&app, swapInterwalOption);

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

        // The window file belongs to a frontend: its shared module (theme, components) must be importable here
        // too. Declared before the engine so that the symlinks outlive it.
        FrontendModules frontendModules;
        QQmlApplicationEngine engine;


        // QString basePath;
        // QString envFrontendPath = QString::fromUtf8(qgetenv("MAIA_FRONTENDS_PATH"));

        // // Ustalenie ścieżki bazowej (dev lub produkcja)
        // if (!envFrontendPath.isEmpty()) {
        //     basePath = envFrontendPath;
        // } else {
        //     basePath = QStringLiteral("/opt/Maia/Maia_") + QStringLiteral(MAIA_VERSION_STRING) + QStringLiteral("/frontends");
        // }

        // // Budowanie ostatecznych ścieżek
        // QString gnomeModulePath = basePath + QStringLiteral("/Gnome/");
        // QString cutefishModulePath = basePath + QStringLiteral("/Cutefish/");
        // QString xplunaModulePath = basePath + QStringLiteral("/XPLuna/");

        // // Dodanie ścieżek importu do silnika QML
        // engine.addImportPath(gnomeModulePath);
        // engine.addImportPath(cutefishModulePath);
        // engine.addImportPath(xplunaModulePath);

        // qDebug() << "[INFO] engine.addImportPath(gnomeModulePath) =" << gnomeModulePath;
        // qDebug() << "[INFO] engine.addImportPath(cutefishModulePath) =" << cutefishModulePath;
        // qDebug() << "[INFO] engine.addImportPath(xplunaModulePath) =" << xplunaModulePath;


        Backend backend(homePath);

        //INIT QML ENGINE ICON PROVIDERS
        //the engine takes ownership of image providers and deletes them in its destructor
        engine.addImageProvider(QLatin1String("backend_app_icon"), new BackendAppsIconsProvider);
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

        engine.rootContext()->setContextProperty(QStringLiteral("HOME"), homePath);
        //Apps List models
        engine.rootContext()->setContextProperty(QStringLiteral("appsListModel"), &filterProxyModel);

        engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);

        //Audio backend
        MAudioBackend audioBackend;
        engine.rootContext()->setContextProperty(QStringLiteral("audioBackend"), &audioBackend);

        QObject::connect(
            &engine,
            &QQmlApplicationEngine::objectCreationFailed,
            &app,
            []() {
                qDebug() << "QCoreApplication::exit(-1); 3";
                QCoreApplication::exit(-1);
            },
            Qt::QueuedConnection);

        const QUrl sourceUrl(sourceOption);
        if (sourceUrl.isLocalFile())
            frontendModules.registerForFile(engine, sourceUrl.toLocalFile());
        engine.load(sourceUrl);

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
    parser.setApplicationDescription(QStringLiteral("Command-line options parser for the application"));
    parser.addHelpOption();
    parser.addVersionOption();

    // Define command-line options
    QCommandLineOption modeOpt(QStringLiteral("mode"), QStringLiteral("Set application mode (server/client)"), QStringLiteral("value"), QStringLiteral("server"));
    QCommandLineOption sourceOpt(QStringLiteral("source"), QStringLiteral("Set QML source URL (e.g., qrc:///Clock3D.qml)"), QStringLiteral("value"));
    QCommandLineOption xOpt(QStringLiteral("x"), QStringLiteral("Set window X position"), QStringLiteral("x"), QStringLiteral("100"));
    QCommandLineOption yOpt(QStringLiteral("y"), QStringLiteral("Set window Y position"), QStringLiteral("y"), QStringLiteral("100"));
    QCommandLineOption widthOpt(QStringLiteral("width"), QStringLiteral("Set window width"), QStringLiteral("width"), QStringLiteral("800"));
    QCommandLineOption heightOpt(QStringLiteral("height"), QStringLiteral("Set window height"), QStringLiteral("height"), QStringLiteral("600"));
    QCommandLineOption swapIntervalOpt(QStringLiteral("swap-interval"), QStringLiteral("Set swap interval"), QStringLiteral("value"), QStringLiteral("1"));
    QCommandLineOption proxyWinAddressOpt(QStringLiteral("proxy-window-addr"),
                                          QStringLiteral("Set proxy window local socket address"),
                                          QStringLiteral("value"),
                                          QStringLiteral("/tmp/maia-XYZ"));
    QCommandLineOption proxyVisibleOpt(QStringLiteral("proxy-visible"),
                                       QStringLiteral("Set proxy window visibility (true/false)"),
                                       QStringLiteral("value"),
                                       QStringLiteral("false"));


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
    swapInterval = 1;
    proxyVisible = false;

    // Parse mode option
    if (parser.isSet(modeOpt)) {
        QString value = parser.value(modeOpt).toLower();
        if (value == QStringLiteral("server") || value == QStringLiteral("client")) {
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
        if (value == QStringLiteral("true")) {
            proxyVisible = true;
        } else if (value == QStringLiteral("false")) {
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
