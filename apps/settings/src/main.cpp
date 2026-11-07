// maia-settings [--page <id>] : the settings of Maia (see ../CMakeLists.txt and ../README.md)
//
// Development options: --screenshot <file.png> [--delay <ms>] saves the window and exits (works
// offscreen); --dark / --light override the theme for that.

#include "FrontendModules.hpp"
#include "MaiaPaths.hpp"
#include "SettingsPages.h"
#include "SingleInstance.h"

#include <QCommandLineParser>
#include <QDir>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTimer>

namespace {

QStringList pageDirectories()
{
    QStringList dirs;
    for (const QString &dir : qEnvironmentVariable("MAIA_SETTINGS_PAGES_PATH").split(QLatin1Char(':'), Qt::SkipEmptyParts))
        dirs.append(dir);
    dirs += QStandardPaths::locateAll(QStandardPaths::GenericDataLocation, QStringLiteral("maia-settings/pages"),
                                      QStandardPaths::LocateDirectory);
    dirs.append(QStringLiteral(MAIA_SETTINGS_PAGES_DIR));
    dirs.removeDuplicates();
    return dirs;
}

// The desktop face is drawn with the Lumen frontend's theme and components
QString frontendShell()
{
    const QString frontends = qEnvironmentVariable("MAIA_FRONTENDS_PATH", QStringLiteral(MAIA_FRONTENDS_DIR));
    const QString name = qEnvironmentVariable("MAIA_SETTINGS_FRONTEND", QStringLiteral("Lumen"));
    return QDir(frontends).filePath(name + QStringLiteral("/shell/Main.qml"));
}

} // namespace

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    // The names of the shell: the frontend's theme settings (light or dark, accent) are read from
    // the same file, ~/.config/maia/<version>/maia.conf
    MaiaPaths::setupApplicationNames();
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Maia Settings"));
    QGuiApplication::setDesktopFileName(QStringLiteral("org.maia.settings"));

    QCommandLineParser parser;
    parser.addHelpOption();
    const QCommandLineOption pageOption(QStringLiteral("page"), QStringLiteral("Page to open, e.g. network."), QStringLiteral("id"));
    const QCommandLineOption screenshotOption(QStringLiteral("screenshot"), QStringLiteral("Save the window to a file and exit."),
                                              QStringLiteral("file"));
    const QCommandLineOption delayOption(QStringLiteral("delay"), QStringLiteral("Wait before the screenshot."), QStringLiteral("ms"),
                                         QStringLiteral("1500"));
    const QCommandLineOption actionOption(QStringLiteral("action"), QStringLiteral("Run a page action after start (testing)."),
                                          QStringLiteral("name"));
    const QCommandLineOption darkOption(QStringLiteral("dark"), QStringLiteral("Dark theme."));
    const QCommandLineOption lightOption(QStringLiteral("light"), QStringLiteral("Light theme."));
    parser.addOptions({pageOption, screenshotOption, delayOption, actionOption, darkOption, lightOption});
    parser.process(app);
    const QString page = parser.value(pageOption);
    const bool screenshot = parser.isSet(screenshotOption);

    SingleInstance instance;
    if (!screenshot && !instance.claim(page))
        return 0;

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral(MAIA_QML_INSTALL_DIR));

    FrontendModules frontendModules;
    if (!frontendModules.registerForFile(engine, frontendShell())) {
        qCritical() << "[Maia Settings] no frontend at" << frontendShell() << "(MAIA_FRONTENDS_PATH, MAIA_SETTINGS_FRONTEND)";
        return 1;
    }

    SettingsPages::setDirectories(pageDirectories());
    QVariantMap properties{{QStringLiteral("initialPage"), page}, {QStringLiteral("testAction"), parser.value(actionOption)}};
    if (parser.isSet(darkOption) || parser.isSet(lightOption))
        properties.insert(QStringLiteral("forceDark"), parser.isSet(darkOption) ? 1 : 0);
    engine.setInitialProperties(properties);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Maia.SettingsKit", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());

    QObject::connect(&instance, &SingleInstance::activationRequested, window, [window](const QString &page) {
        QMetaObject::invokeMethod(window, "activate", Q_ARG(QVariant, page));
    });

    if (screenshot) {
        const int delay = parser.value(delayOption).toInt();
        QTimer::singleShot(delay, window, [window, file = parser.value(screenshotOption)] {
            const bool saved = window->grabWindow().save(file);
            qInfo() << "[Maia Settings] screenshot" << file << (saved ? "saved" : "FAILED");
            QCoreApplication::exit(saved ? 0 : 1);
        });
    }
    return app.exec();
}
