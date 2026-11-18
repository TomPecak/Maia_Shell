// CrossProcessState between real processes: hosts and participants are crossprocessstate-peer
// programs (tests/peer.cpp) on a socket of their own; the test drives them through their standard
// input and reads what they see. In this process: objects without a host, and the wire values.

#include "CrossProcessState.h"
#include "Link.h"

#include <QColor>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QTimer>
#include <QJsonDocument>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

#include <memory>
#include <signal.h>

using namespace MaiaCrossProcessState;

namespace {

constexpr int kTimeout = 5000;

// One peer process and the lines it printed
class Peer
{
public:
    Peer(const QString &socketPath, const QStringList &arguments)
    {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert(QStringLiteral("MAIA_CROSS_PROCESS_STATE_SOCKET"), socketPath);
        env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen"));
        m_process.setProcessEnvironment(env);
        m_process.setProcessChannelMode(QProcess::SeparateChannels);
        QObject::connect(&m_process, &QProcess::readyReadStandardOutput, [this] {
            m_buffer.append(m_process.readAllStandardOutput());
            qsizetype end;
            while ((end = m_buffer.indexOf('\n')) >= 0) {
                m_lines.append(QString::fromUtf8(m_buffer.left(end)));
                m_buffer.remove(0, end + 1);
            }
        });
        QObject::connect(&m_process, &QProcess::readyReadStandardError, [this] { m_errors.append(m_process.readAllStandardError()); });
        m_process.start(QStringLiteral(PEER_PROGRAM), arguments);
    }

    ~Peer()
    {
        if (m_process.state() != QProcess::NotRunning) {
            m_process.kill();
            m_process.waitForFinished(1000);
        }
    }

    bool started() { return m_process.waitForStarted(kTimeout); }
    void send(const QString &command) { m_process.write((command + QLatin1Char('\n')).toUtf8()); }
    bool saw(const QString &line) const { return m_lines.contains(line); }
    // The last line starting with `prefix`
    QString last(const QString &prefix) const
    {
        for (qsizetype i = m_lines.size() - 1; i >= 0; --i) {
            if (m_lines[i].startsWith(prefix))
                return m_lines[i];
        }
        return {};
    }
    int count(const QString &prefix) const
    {
        return int(std::count_if(m_lines.cbegin(), m_lines.cend(), [&prefix](const QString &l) { return l.startsWith(prefix); }));
    }
    bool synced() const { return last(QStringLiteral("synced ")) == QLatin1String("synced true"); }
    // Waits for a line, woken by the process's output (no sleeping steps): for timing
    bool waitForLine(const QString &line, int timeout = kTimeout)
    {
        if (saw(line))
            return true;
        QEventLoop loop;
        QTimer::singleShot(timeout, &loop, &QEventLoop::quit);
        const auto connection = QObject::connect(&m_process, &QProcess::readyReadStandardOutput, &loop, [&] {
            if (saw(line))
                loop.quit();
        }, Qt::QueuedConnection);
        loop.exec();
        QObject::disconnect(connection);
        return saw(line);
    }
    void clear() { m_lines.clear(); }
    QString errors() const { return QString::fromUtf8(m_errors); }

    void quit()
    {
        send(QStringLiteral("quit"));
        QVERIFY(m_process.waitForFinished(kTimeout));
    }
    void crash()
    {
        ::kill(pid_t(m_process.processId()), SIGKILL);
        QVERIFY(m_process.waitForFinished(kTimeout));
    }

private:
    QProcess m_process;
    QByteArray m_buffer;
    QByteArray m_errors;
    QStringList m_lines;
};

QString json(const QVariant &value)
{
    return QString::fromUtf8(QJsonDocument::fromVariant(QVariantList{value}).toJson(QJsonDocument::Compact)).mid(1).chopped(1);
}

} // namespace

class TestCrossProcessState : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<QTemporaryDir> m_dir;
    QString m_socket;

    std::unique_ptr<Peer> start(const QStringList &arguments = {})
    {
        auto peer = std::make_unique<Peer>(m_socket, arguments);
        if (!peer->started())
            return nullptr;
        if (!QTest::qWaitFor([&] { return peer->saw(QStringLiteral("ready")); }, kTimeout))
            qWarning() << "a peer did not start:" << peer->errors();
        return peer;
    }

    static bool waitSynced(const Peer &peer) { return QTest::qWaitFor([&] { return peer.synced(); }, kTimeout); }

private Q_SLOTS:
    void init()
    {
        // A socket of its own for every test: no state is carried over
        m_dir = std::make_unique<QTemporaryDir>();
        QVERIFY(m_dir->isValid());
        m_socket = m_dir->filePath(QStringLiteral("s.sock"));
    }

    void valuesOfEveryTypeReachEveryProcess()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b);
        QVERIFY(host->synced());
        QVERIFY(waitSynced(*a) && waitSynced(*b));

        const QList<QPair<QString, QString>> values = {
            {QStringLiteral("flag"), QStringLiteral("true")},
            {QStringLiteral("count"), QStringLiteral("7")},
            {QStringLiteral("ratio"), QStringLiteral("0.25")},
            {QStringLiteral("text"), QStringLiteral("\"zażółć\"")},
            {QStringLiteral("list"), QStringLiteral("[1,\"x\",[true]]")},
            {QStringLiteral("map"), QStringLiteral("{\"a\":1,\"b\":{\"c\":\"d\"}}")},
            {QStringLiteral("tint"), QStringLiteral("\"#ff0000\"")},
            {QStringLiteral("link"), QStringLiteral("\"file:///home/a/x.png\"")},
        };
        for (const auto &[property, value] : values) {
            a->send(QStringLiteral("set %1 %2").arg(property, value));
            const QString seen = QStringLiteral("changed %1 %2").arg(property, value);
            QTRY_VERIFY2_WITH_TIMEOUT(b->saw(seen), qPrintable(seen + QLatin1String(" / ") + b->last(QStringLiteral("changed ") + property)), kTimeout);
            QTRY_VERIFY_WITH_TIMEOUT(host->saw(seen), kTimeout);
        }
        // From the host to the participants
        host->send(QStringLiteral("set text \"from the host\""));
        QTRY_VERIFY_WITH_TIMEOUT(a->saw(QStringLiteral("changed text \"from the host\"")), kTimeout);
        QTRY_VERIFY_WITH_TIMEOUT(b->saw(QStringLiteral("changed text \"from the host\"")), kTimeout);
    }

    void aLateParticipantGetsTheCurrentState()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        QVERIFY(host && a && waitSynced(*a));
        a->send(QStringLiteral("set text \"now\""));
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"now\"")), kTimeout);
        auto late = start();
        QVERIFY(late && waitSynced(*late));
        QVERIFY(late->saw(QStringLiteral("changed text \"now\"")));
    }

    void aParticipantBeforeItsHostKeepsItsChange()
    {
        auto a = start();
        QVERIFY(a);
        QVERIFY(!a->synced());
        // Without a host: its own value only
        a->send(QStringLiteral("set text \"early\""));
        QTRY_VERIFY_WITH_TIMEOUT(a->saw(QStringLiteral("changed text \"early\"")), kTimeout);
        QElapsedTimer timer;
        timer.start();
        auto host = start({QStringLiteral("--host")});
        QVERIFY(host);
        // The host's socket appears: the participant connects (inotify, no polling)
        QVERIFY(waitSynced(*a));
        qInfo() << "a waiting participant connected" << timer.elapsed() << "ms after the host was started";
        // A changed value wins over the host's declared default
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"early\"")), kTimeout);
    }

    void aRestartedHostGetsTheStateBack()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b && waitSynced(*a) && waitSynced(*b));
        a->send(QStringLiteral("set text \"kept\""));
        b->send(QStringLiteral("set count 42"));
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"kept\"")) && host->saw(QStringLiteral("changed count 42")), kTimeout);

        host->quit();
        QTRY_VERIFY_WITH_TIMEOUT(!a->synced() && !b->synced(), kTimeout);
        auto again = start({QStringLiteral("--host")});
        QVERIFY(again);
        QVERIFY(waitSynced(*a) && waitSynced(*b));
        QTRY_VERIFY_WITH_TIMEOUT(again->saw(QStringLiteral("changed text \"kept\"")), kTimeout);
        QTRY_VERIFY_WITH_TIMEOUT(again->saw(QStringLiteral("changed count 42")), kTimeout);
        // And it goes on as before
        again->send(QStringLiteral("set flag true"));
        QTRY_VERIFY_WITH_TIMEOUT(a->saw(QStringLiteral("changed flag true")) && b->saw(QStringLiteral("changed flag true")), kTimeout);
    }

    void aCrashedHostIsReplaced()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        QVERIFY(host && a && waitSynced(*a));
        a->send(QStringLiteral("set text \"before the crash\""));
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"before the crash\"")), kTimeout);
        // No clean end: its socket and its lock stay behind
        host->crash();
        QVERIFY(QFile::exists(m_socket));
        QTRY_VERIFY_WITH_TIMEOUT(!a->synced(), kTimeout);
        auto again = start({QStringLiteral("--host")});
        QVERIFY(again);
        QVERIFY(again->synced());
        QVERIFY(waitSynced(*a));
        QTRY_VERIFY_WITH_TIMEOUT(again->saw(QStringLiteral("changed text \"before the crash\"")), kTimeout);
    }

    void aSecondHostTakesPartInstead()
    {
        auto host = start({QStringLiteral("--host")});
        auto second = start({QStringLiteral("--host")});
        QVERIFY(host && second);
        QVERIFY(waitSynced(*second));
        QTRY_VERIFY_WITH_TIMEOUT(second->errors().contains(QLatin1String("takes part instead")), kTimeout);
        second->send(QStringLiteral("set text \"one state\""));
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"one state\"")), kTimeout);
    }

    void writesAtOnceEndTheSameEverywhere()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b && waitSynced(*a) && waitSynced(*b));
        for (int i = 0; i < 50; ++i) {
            a->send(QStringLiteral("set text \"a%1\"").arg(i));
            b->send(QStringLiteral("set text \"b%1\"").arg(i));
        }
        // Quiet again: one value in all three
        QTest::qWait(500);
        const QString hostValue = host->last(QStringLiteral("changed text "));
        QVERIFY(!hostValue.isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(a->last(QStringLiteral("changed text ")), hostValue, kTimeout);
        QTRY_COMPARE_WITH_TIMEOUT(b->last(QStringLiteral("changed text ")), hostValue, kTimeout);
    }

    void anEventReachesEveryOtherProcessOnce()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b && waitSynced(*a) && waitSynced(*b));
        a->send(QStringLiteral("fire 42 hello"));
        const QString event = QStringLiteral("event ping [42,\"hello\"]");
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(event) && b->saw(event), kTimeout);
        QTest::qWait(200);
        // Each once: the sender's own handler ran when it emitted, nothing came back to it
        QCOMPARE(a->count(event), 1);
        QCOMPARE(b->count(event), 1);
        QCOMPARE(host->count(event), 1);
        // A JavaScript object as the argument
        a->send(QStringLiteral("note {\"items\":[1,\"two\"],\"ok\":true}"));
        const QString note = QStringLiteral("event note {\"items\":[1,\"two\"],\"ok\":true}");
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(note) && b->saw(note), kTimeout);
    }

    void aBurstOfChangesIsOneMessage()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b && waitSynced(*a) && waitSynced(*b));
        // 10000 assignments in one turn of a's event loop
        a->send(QStringLiteral("burst 10000"));
        QTRY_VERIFY_WITH_TIMEOUT(b->saw(QStringLiteral("changed count 10000")), kTimeout);
        QTest::qWait(200);
        QCOMPARE(b->count(QStringLiteral("changed count ")), 1);
        QCOMPARE(host->count(QStringLiteral("changed count ")), 1);
    }

    void aChangeArrivesQuickly()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b && waitSynced(*a) && waitSynced(*b));
        // The round trip of the test (its pipes, the peers' event loops) is included
        QElapsedTimer timer;
        timer.start();
        qint64 longest = 0;
        for (int i = 0; i < 20; ++i) {
            const QString value = QStringLiteral("\"t%1\"").arg(i);
            timer.restart();
            a->send(QStringLiteral("set text ") + value);
            QVERIFY(b->waitForLine(QStringLiteral("changed text ") + value));
            longest = qMax(longest, timer.nsecsElapsed());
        }
        qInfo() << "a change reached the other participant in at most" << longest / 1000 << "µs (20 changes)";
        QVERIFY(longest < 100 * 1000 * 1000);
    }

    void objectsOfOneProcessShareWithoutAHost()
    {
        auto a = start({QStringLiteral("--twin")});
        QVERIFY(a);
        a->send(QStringLiteral("set text \"twins\""));
        QTRY_VERIFY_WITH_TIMEOUT(a->saw(QStringLiteral("twin text \"twins\"")), kTimeout);
        QVERIFY(!a->synced());
    }

    // --- In this process ---

    void declaredValuesAndSignalsAreFoundByReflection()
    {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MAIA_QML_BUILD_DIR));
        Link link(m_socket);
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Maia.CrossProcessState
            Item {
                property alias first: one
                property alias second: two
                function sayHello() { one.hello({ k: 3 }) }
                CrossProcessState { id: one; category: "Local"; property int value: 1; property var list: [1, 2]; signal hello(var payload) }
                CrossProcessState { id: two; category: "Local"; property int value: 1; property var list: []; signal hello(var payload)
                                    property var heard: null; onHello: payload => heard = payload }
            })", QUrl());
        // The link of the test, not the process's own
        QObject *root = component.beginCreate(engine.rootContext());
        QVERIFY2(root, qPrintable(component.errorString()));
        const auto objects = root->findChildren<CrossProcessState *>();
        QCOMPARE(objects.size(), 2);
        for (CrossProcessState *object : objects)
            object->setLink(&link);
        component.completeCreate();
        std::unique_ptr<QObject> owner(root);

        QObject *one = root->property("first").value<QObject *>();
        QObject *two = root->property("second").value<QObject *>();
        // Different declared defaults: the one this process knew first (the first object completed)
        // wins for both; the two are never different
        QCOMPARE(Link::wireValue(one->property("list")), Link::wireValue(two->property("list")));
        one->setProperty("value", 5);
        QCOMPARE(two->property("value").toInt(), 5);
        QVERIFY(QMetaObject::invokeMethod(root, "sayHello"));
        QCOMPARE(Link::wireValue(two->property("heard")).toMap().value(QStringLiteral("k")).toInt(), 3);
        QVERIFY(!one->property("synced").toBool());
    }

    void wireValuesAreWhatTravels()
    {
        QCOMPARE(Link::wireValue(QColor(Qt::red)).value<QColor>(), QColor(Qt::red));
        QCOMPARE(Link::wireValue(QUrl(QStringLiteral("file:///x"))).toUrl(), QUrl(QStringLiteral("file:///x")));
        // Nested lists and maps stay; something that cannot be written does not travel
        const QVariant nested = QVariantMap{{QStringLiteral("a"), QVariantList{1, QStringLiteral("b")}}};
        QCOMPARE(Link::wireValue(nested), nested);
        QVERIFY(!Link::wireValue(QVariant::fromValue(static_cast<QObject *>(this))).isValid());
        QCOMPARE(json(QVariantList{1, 2}), QStringLiteral("[1,2]"));
    }
};

QTEST_MAIN(TestCrossProcessState)
#include "tst_crossprocessstate.moc"
