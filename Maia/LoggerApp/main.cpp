#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "LoggerBackend.hpp"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    LoggerBackend backend;

    QQmlApplicationEngine engine;

    engine.rootContext()->setContextProperty("backend", &backend);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("Logger", "Main");

    return app.exec();
}
