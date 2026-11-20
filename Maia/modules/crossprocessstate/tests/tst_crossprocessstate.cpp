// CrossProcessState between real processes: hosts and participants are crossprocessstate-peer
// programs (tests/peer.cpp) on a socket of their own; the test drives them through their standard
// input and reads what they see. In this process: objects without a host, and the wire values.

#include "CrossProcessState.h"
#include "Link.h"

#include <QColor>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QTimer>
#include <QFile>
#include <QJsonDocument>
#include <QLocalSocket>
#include <QProcess>
#include <QRegularExpression>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>

#include <memory>
#include <signal.h>
#include <unistd.h>

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
    bool running() const { return m_process.state() == QProcess::Running; }
    // Processor time used so far, in clock ticks (user + system, /proc/<pid>/stat)
    qint64 cpuTicks() const
    {
        QFile stat(QStringLiteral("/proc/%1/stat").arg(m_process.processId()));
        if (!stat.open(QIODevice::ReadOnly))
            return -1;
        // The fields after the command name (which may contain spaces), from field 3 on
        const QByteArray line = stat.readAll();
        const QList<QByteArray> fields = line.mid(line.lastIndexOf(')') + 2).split(' ');
        return fields.value(11).toLongLong() + fields.value(12).toLongLong();
    }
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
    // The socket of this process's own link (Link::instance(), used by objects QML creates itself:
    // Instantiator, Loader); each test uses its own category on it
    QTemporaryDir m_processDir;
    QString m_processSocket;

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

    // An object of `qml`, completed on `link`
    static CrossProcessState *create(QQmlEngine &engine, const QByteArray &qml, Link *link)
    {
        QQmlComponent component(&engine);
        component.setData("import Maia.CrossProcessState\n" + qml, QUrl());
        auto *object = qobject_cast<CrossProcessState *>(component.beginCreate(engine.rootContext()));
        if (!object) {
            qWarning() << component.errorString();
            return nullptr;
        }
        object->setLink(link);
        component.completeCreate();
        return object;
    }

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(m_processDir.isValid());
        m_processSocket = m_processDir.filePath(QStringLiteral("p.sock"));
        qputenv("MAIA_CROSS_PROCESS_STATE_SOCKET", m_processSocket.toUtf8());
    }

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

    void aKilledParticipantDoesNotDisturbTheOthers()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b && waitSynced(*a) && waitSynced(*b));
        a->crash();
        b->send(QStringLiteral("set text \"after a's crash\""));
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"after a's crash\"")), kTimeout);
        // It comes back with the state as it is
        auto again = start();
        QVERIFY(again && waitSynced(*again));
        QVERIFY(again->saw(QStringLiteral("changed text \"after a's crash\"")));
    }

    void twoHostsStartingAtOnceAreOneHost()
    {
        for (int round = 0; round < 5; ++round) {
            init();
            // No wait between them: both race for the lock
            auto first = std::make_unique<Peer>(m_socket, QStringList{QStringLiteral("--host")});
            auto second = std::make_unique<Peer>(m_socket, QStringList{QStringLiteral("--host")});
            QVERIFY(first->started() && second->started());
            QVERIFY(waitSynced(*first) && waitSynced(*second));
            const int warned = int(first->errors().contains(QLatin1String("takes part instead")))
                + int(second->errors().contains(QLatin1String("takes part instead")));
            QTRY_COMPARE_WITH_TIMEOUT(int(first->errors().contains(QLatin1String("takes part instead")))
                                          + int(second->errors().contains(QLatin1String("takes part instead"))),
                                      1, kTimeout);
            Q_UNUSED(warned)
            first->send(QStringLiteral("set count %1").arg(round + 1));
            QTRY_VERIFY_WITH_TIMEOUT(second->saw(QStringLiteral("changed count %1").arg(round + 1)), kTimeout);
        }
    }

    void aWouldBeHostTakesOverWhenTheHostDies()
    {
        auto host = start({QStringLiteral("--host")});
        auto spare = start({QStringLiteral("--host")});
        auto a = start();
        QVERIFY(host && spare && a && waitSynced(*spare) && waitSynced(*a));
        a->send(QStringLiteral("set text \"survives\""));
        QTRY_VERIFY_WITH_TIMEOUT(spare->saw(QStringLiteral("changed text \"survives\"")), kTimeout);
        host->crash();
        // The spare hosts now (synced stays true there, or comes back at once); a reconnects to it
        QTRY_VERIFY_WITH_TIMEOUT(spare->synced(), kTimeout);
        QVERIFY(waitSynced(*a));
        a->send(QStringLiteral("set count 99"));
        QTRY_VERIFY_WITH_TIMEOUT(spare->saw(QStringLiteral("changed count 99")), kTimeout);
        auto late = start();
        QVERIFY(late && waitSynced(*late));
        QVERIFY(late->saw(QStringLiteral("changed text \"survives\"")));
        QVERIFY(late->saw(QStringLiteral("changed count 99")));
    }

    void changesWithoutAHostAreNotLost()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        auto b = start();
        QVERIFY(host && a && b && waitSynced(*a) && waitSynced(*b));
        host->crash();
        QTRY_VERIFY_WITH_TIMEOUT(!a->synced() && !b->synced(), kTimeout);
        a->send(QStringLiteral("set text \"while nobody hosted\""));
        QTRY_VERIFY_WITH_TIMEOUT(a->saw(QStringLiteral("changed text \"while nobody hosted\"")), kTimeout);
        auto again = start({QStringLiteral("--host")});
        QVERIFY(again && waitSynced(*a) && waitSynced(*b));
        QTRY_VERIFY_WITH_TIMEOUT(again->saw(QStringLiteral("changed text \"while nobody hosted\"")), kTimeout);
        QTRY_VERIFY_WITH_TIMEOUT(b->saw(QStringLiteral("changed text \"while nobody hosted\"")), kTimeout);
    }

    void aFlappingHostEndsInOneState()
    {
        auto a = start();
        auto b = start();
        QVERIFY(a && b);
        for (int i = 0; i < 5; ++i) {
            auto host = start({QStringLiteral("--host")});
            QVERIFY(host && waitSynced(*a) && waitSynced(*b));
            a->send(QStringLiteral("set count %1").arg(i + 1));
            QTRY_VERIFY_WITH_TIMEOUT(b->saw(QStringLiteral("changed count %1").arg(i + 1)), kTimeout);
            if (i % 2)
                host->crash();
            else
                host->quit();
            QTRY_VERIFY_WITH_TIMEOUT(!a->synced() && !b->synced(), kTimeout);
        }
        auto last = start({QStringLiteral("--host")});
        QVERIFY(last && waitSynced(*a) && waitSynced(*b));
        QTRY_VERIFY_WITH_TIMEOUT(last->saw(QStringLiteral("changed count 5")), kTimeout);
    }

    void manyParticipantsSeeEachEventOnce()
    {
        auto host = start({QStringLiteral("--host")});
        QVERIFY(host);
        std::vector<std::unique_ptr<Peer>> peers;
        for (int i = 0; i < 10; ++i) {
            peers.push_back(start());
            QVERIFY(peers.back());
        }
        for (const auto &peer : peers)
            QVERIFY(waitSynced(*peer));
        peers[3]->send(QStringLiteral("fire 7 seven"));
        peers[5]->send(QStringLiteral("set text \"ten\""));
        const QString event = QStringLiteral("event ping [7,\"seven\"]");
        for (const auto &peer : peers) {
            QTRY_VERIFY_WITH_TIMEOUT(peer->saw(event), kTimeout);
            QTRY_VERIFY_WITH_TIMEOUT(peer->saw(QStringLiteral("changed text \"ten\"")), kTimeout);
        }
        QTest::qWait(200);
        for (const auto &peer : peers)
            QCOMPARE(peer->count(event), 1);
        QCOMPARE(host->count(event), 1);
    }

    void aBrokenProcessCannotHurtTheHost()
    {
        auto host = start({QStringLiteral("--host")});
        auto a = start();
        QVERIFY(host && a && waitSynced(*a));
        const auto rogue = [this](const QByteArray &bytes) {
            QLocalSocket socket;
            socket.connectToServer(m_socket);
            QVERIFY(socket.waitForConnected(kTimeout));
            socket.write(bytes);
            QVERIFY(socket.waitForBytesWritten(kTimeout));
            // The host closes the connection
            QVERIFY(socket.state() == QLocalSocket::UnconnectedState || socket.waitForDisconnected(kTimeout));
        };
        // A frame claiming 2 GiB, a frame that is no message, a Hello of another version
        rogue(QByteArray::fromHex("7fffffff"));
        rogue(QByteArray::fromHex("00000004ffffffff"));
        QByteArray hello;
        {
            QDataStream out(&hello, QIODevice::WriteOnly);
            out.setVersion(QDataStream::Qt_6_0);
            out << quint8(1) << quint32(999);
        }
        rogue(Protocol::frame(hello));
        // The host still serves the others
        QVERIFY(host->running());
        a->send(QStringLiteral("set text \"still fine\""));
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"still fine\"")), kTimeout);
    }

    void aWaitingParticipantUsesNoProcessorTime()
    {
        // A host that crashed: its socket file stays, nobody answers it
        auto host = start({QStringLiteral("--host")});
        QVERIFY(host);
        host->crash();
        QVERIFY(QFile::exists(m_socket));
        auto a = start();
        QVERIFY(a);
        QTest::qWait(300);
        const qint64 before = a->cpuTicks();
        QVERIFY(before >= 0);
        QTest::qWait(2000);
        const qint64 used = a->cpuTicks() - before;
        qInfo() << "a participant waiting for a host used" << used * 1000 / ::sysconf(_SC_CLK_TCK) << "ms of processor time in 2 s";
        // Nothing polls: at most scheduler noise
        QVERIFY2(used <= 2, qPrintable(QString::number(used)));
        QVERIFY(!a->synced());
    }

    void objectsOfOneProcessShareWithoutAHost()
    {
        auto a = start({QStringLiteral("--twin")});
        QVERIFY(a);
        a->send(QStringLiteral("set text \"twins\""));
        QTRY_VERIFY_WITH_TIMEOUT(a->saw(QStringLiteral("twin text \"twins\"")), kTimeout);
        QVERIFY(!a->synced());
    }

    // --- Many objects in one process ---

    void fiftyObjectsOfOneCategoryJoinOnce()
    {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MAIA_QML_BUILD_DIR));
        Link host(m_processSocket);
        std::unique_ptr<CrossProcessState> hostObject(
            create(engine, "CrossProcessState { category: \"Fifty\"; host: true; property int value: 0 }", &host));
        QVERIFY(hostObject && host.isHost());

        // Fifty objects QML makes itself: they use the process's own link, a participant
        Link *own = Link::instance();
        const int joinsBefore = own->joinsSent();
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQml
            import QtQml.Models
            import Maia.CrossProcessState
            Instantiator { model: 50; delegate: CrossProcessState { category: "Fifty"; property int value: 0 } })", QUrl());
        std::unique_ptr<QObject> instantiator(component.create());
        QVERIFY2(instantiator, qPrintable(component.errorString()));
        QTRY_VERIFY_WITH_TIMEOUT(own->isSynced(QStringLiteral("Fifty")), kTimeout);
        QCOMPARE(own->joinsSent() - joinsBefore, 1);

        hostObject->setProperty("value", 5);
        QTRY_VERIFY_WITH_TIMEOUT([&] {
            for (int i = 0; i < 50; ++i) {
                QObject *object = nullptr;
                QMetaObject::invokeMethod(instantiator.get(), "objectAt", Q_RETURN_ARG(QObject *, object), Q_ARG(int, i));
                if (!object || object->property("value").toInt() != 5)
                    return false;
            }
            return true;
        }(), kTimeout);
        // A change in one of them: the host and the 49 others
        QObject *tenth = nullptr;
        QMetaObject::invokeMethod(instantiator.get(), "objectAt", Q_RETURN_ARG(QObject *, tenth), Q_ARG(int, 9));
        tenth->setProperty("value", 6);
        QTRY_COMPARE_WITH_TIMEOUT(hostObject->property("value").toInt(), 6, kTimeout);
        QObject *last = nullptr;
        QMetaObject::invokeMethod(instantiator.get(), "objectAt", Q_RETURN_ARG(QObject *, last), Q_ARG(int, 49));
        QCOMPARE(last->property("value").toInt(), 6);
    }

    void twoHostObjectsInOneProcessAreOneHost()
    {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MAIA_QML_BUILD_DIR));
        Link link(m_socket);
        // The second one is no second host: no warning
        QTest::failOnWarning(QRegularExpression(QStringLiteral("takes part instead")));
        std::unique_ptr<CrossProcessState> first(create(engine, "CrossProcessState { category: \"TwoHosts\"; host: true; property int value: 1 }", &link));
        std::unique_ptr<CrossProcessState> second(create(engine, "CrossProcessState { category: \"TwoHosts\"; host: true; property int value: 1 }", &link));
        QVERIFY(first && second && link.isHost());
        QVERIFY(first->synced() && second->synced());
        first->setProperty("value", 2);
        QCOMPARE(second->property("value").toInt(), 2);
        auto peer = start();
        QVERIFY(peer && waitSynced(*peer));
    }

    void aRecreatedObjectGetsTheCurrentValue()
    {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MAIA_QML_BUILD_DIR));
        QQmlComponent component(&engine);
        component.setData(R"(
            import QtQuick
            import Maia.CrossProcessState
            Item {
                property alias keeper: keeper
                property alias loader: loader
                CrossProcessState { id: keeper; category: "Recreated"; property string text: "first" }
                Loader { id: loader; active: false
                         sourceComponent: Component { CrossProcessState { category: "Recreated"; property string text: "first" } } }
            })", QUrl());
        std::unique_ptr<QObject> root(component.create());
        QVERIFY2(root, qPrintable(component.errorString()));
        QObject *keeper = root->property("keeper").value<QObject *>();
        QObject *loader = root->property("loader").value<QObject *>();
        keeper->setProperty("text", QStringLiteral("changed"));
        loader->setProperty("active", true);
        QCOMPARE(loader->property("item").value<QObject *>()->property("text").toString(), QStringLiteral("changed"));
        // Gone and made again (a Loader, a delegate): never its declared value once there is a newer one
        loader->setProperty("active", false);
        keeper->setProperty("text", QStringLiteral("again"));
        loader->setProperty("active", true);
        QObject *item = loader->property("item").value<QObject *>();
        QCOMPARE(item->property("text").toString(), QStringLiteral("again"));
        item->setProperty("text", QStringLiteral("from the new one"));
        QCOMPARE(keeper->property("text").toString(), QStringLiteral("from the new one"));
    }

    void theHostGoesOnWhenItsObjectIsGone()
    {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(MAIA_QML_BUILD_DIR));
        Link link(m_socket);
        std::unique_ptr<CrossProcessState> object(
            create(engine, "CrossProcessState { category: \"Test\"; host: true; property string text: \"kept\" }", &link));
        QVERIFY(object && link.isHost());
        auto a = start();
        QVERIFY(a && waitSynced(*a));
        QTRY_VERIFY_WITH_TIMEOUT(a->saw(QStringLiteral("changed text \"kept\"")), kTimeout);
        // The process still hosts: it keeps the session's state for the others
        object.reset();
        QVERIFY(link.isHost());
        auto b = start();
        QVERIFY(b && waitSynced(*b));
        QVERIFY(b->saw(QStringLiteral("changed text \"kept\"")));
        a->send(QStringLiteral("set text \"still hosted\""));
        QTRY_VERIFY_WITH_TIMEOUT(b->saw(QStringLiteral("changed text \"still hosted\"")), kTimeout);
    }

    void twinsInAParticipantGetAChangeOnceEach()
    {
        auto host = start({QStringLiteral("--host")});
        auto twins = start({QStringLiteral("--twin")});
        QVERIFY(host && twins && waitSynced(*twins));
        host->send(QStringLiteral("set text \"to both\""));
        QTRY_VERIFY_WITH_TIMEOUT(twins->saw(QStringLiteral("changed text \"to both\"")) && twins->saw(QStringLiteral("twin text \"to both\"")), kTimeout);
        QTest::qWait(200);
        QCOMPARE(twins->count(QStringLiteral("changed text \"to both\"")), 1);
        QCOMPARE(twins->count(QStringLiteral("twin text \"to both\"")), 1);
        // One of them changes it: its twin at once, the host once
        twins->send(QStringLiteral("set text \"from a twin\""));
        QTRY_VERIFY_WITH_TIMEOUT(host->saw(QStringLiteral("changed text \"from a twin\"")), kTimeout);
        QTRY_VERIFY_WITH_TIMEOUT(twins->saw(QStringLiteral("twin text \"from a twin\"")), kTimeout);
        QTest::qWait(200);
        QCOMPARE(host->count(QStringLiteral("changed text \"from a twin\"")), 1);
        QCOMPARE(twins->count(QStringLiteral("twin text \"from a twin\"")), 1);
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
