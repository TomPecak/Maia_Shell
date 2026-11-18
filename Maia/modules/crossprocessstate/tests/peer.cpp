// A process taking part in a CrossProcessState, for tests: loads one (or with --twin two) in QML and
// reports what it sees on its standard output, one line each:
//   ready | synced true|false | changed <property> <json> | event ping <json args> | twin text <json>
// Driven through its standard input (read on a socket notifier, the event loop never waits):
//   set <property> <json> | fire <number> <word> | note <json> | burst <count> | quit
//
//   crossprocessstate-peer [--host] [--twin]      (the socket: $MAIA_CROSS_PROCESS_STATE_SOCKET)

#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QSocketNotifier>

#include <cstdio>
#include <unistd.h>

namespace {

class Reporter : public QObject
{
    Q_OBJECT

public:
    Q_INVOKABLE void say(const QString &line)
    {
        std::fputs(qPrintable(line + QLatin1Char('\n')), stdout);
        std::fflush(stdout);
    }
};

const char *kQml = R"(
import QtQuick
import Maia.CrossProcessState

Item {
    function assign(name, json) { shared[name] = JSON.parse(json) }
    function fire(number, word) { shared.ping(number, word) }
    function note(json) { shared.note(JSON.parse(json)) }
    function burst(count) { for (let i = 1; i <= count; ++i) shared.count = i }

    CrossProcessState {
        id: shared
        objectName: "shared"
        category: "Test"
        host: HOST

        property bool flag: false
        property int count: 0
        property real ratio: 0.5
        property string text: "default"
        property var list: []
        property var map: ({})
        property color tint: "black"
        property url link: ""
        signal ping(int number, string word)
        signal note(var payload)

        onSyncedChanged: out.say("synced " + synced)
        onFlagChanged: out.say("changed flag " + JSON.stringify(flag))
        onCountChanged: out.say("changed count " + JSON.stringify(count))
        onRatioChanged: out.say("changed ratio " + JSON.stringify(ratio))
        onTextChanged: out.say("changed text " + JSON.stringify(text))
        onListChanged: out.say("changed list " + JSON.stringify(list))
        onMapChanged: out.say("changed map " + JSON.stringify(map))
        onTintChanged: out.say("changed tint " + JSON.stringify(String(tint)))
        onLinkChanged: out.say("changed link " + JSON.stringify(String(link)))
        onPing: (number, word) => out.say("event ping " + JSON.stringify([number, word]))
        onNote: payload => out.say("event note " + JSON.stringify(payload))
    }

    TWIN
}
)";

const char *kTwin = R"(
    CrossProcessState {
        category: "Test"
        property string text: "default"
        onTextChanged: out.say("twin text " + JSON.stringify(text))
    }
)";

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QStringList args = app.arguments();
    const bool host = args.contains(QStringLiteral("--host"));
    const bool twin = args.contains(QStringLiteral("--twin"));

    QQmlEngine engine;
    engine.addImportPath(QStringLiteral(MAIA_QML_BUILD_DIR));
    Reporter reporter;
    engine.rootContext()->setContextProperty(QStringLiteral("out"), &reporter);

    QString qml = QString::fromUtf8(kQml);
    qml.replace(QStringLiteral("HOST"), host ? QStringLiteral("true") : QStringLiteral("false"));
    qml.replace(QStringLiteral("TWIN"), twin ? QString::fromUtf8(kTwin) : QString());
    QQmlComponent component(&engine);
    component.setData(qml.toUtf8(), QUrl());
    QObject *root = component.create();
    if (!root) {
        std::fputs(qPrintable(component.errorString()), stderr);
        return 1;
    }
    reporter.say(QStringLiteral("ready"));
    QObject *shared = root->findChild<QObject *>(QStringLiteral("shared"));
    reporter.say(QStringLiteral("synced ") + (shared && shared->property("synced").toBool() ? QStringLiteral("true") : QStringLiteral("false")));

    QSocketNotifier input(STDIN_FILENO, QSocketNotifier::Read);
    QByteArray pending;
    QObject::connect(&input, &QSocketNotifier::activated, &app, [&] {
        char buffer[4096];
        const ssize_t n = ::read(STDIN_FILENO, buffer, sizeof buffer);
        if (n <= 0) {
            app.quit();
            return;
        }
        pending.append(buffer, n);
        qsizetype end;
        while ((end = pending.indexOf('\n')) >= 0) {
            const QString line = QString::fromUtf8(pending.left(end));
            pending.remove(0, end + 1);
            const QString command = line.section(QLatin1Char(' '), 0, 0);
            if (command == QLatin1String("set")) {
                QMetaObject::invokeMethod(root, "assign", Q_ARG(QVariant, line.section(QLatin1Char(' '), 1, 1)),
                                          Q_ARG(QVariant, line.section(QLatin1Char(' '), 2)));
            } else if (command == QLatin1String("fire")) {
                QMetaObject::invokeMethod(root, "fire", Q_ARG(QVariant, line.section(QLatin1Char(' '), 1, 1).toInt()),
                                          Q_ARG(QVariant, line.section(QLatin1Char(' '), 2)));
            } else if (command == QLatin1String("note")) {
                QMetaObject::invokeMethod(root, "note", Q_ARG(QVariant, line.section(QLatin1Char(' '), 1)));
            } else if (command == QLatin1String("burst")) {
                QMetaObject::invokeMethod(root, "burst", Q_ARG(QVariant, line.section(QLatin1Char(' '), 1, 1).toInt()));
            } else if (command == QLatin1String("quit")) {
                app.quit();
            }
        }
    });
    return app.exec();
}

#include "peer.moc"
