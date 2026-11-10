// Maia.Session against the real session service: a session with a fake compositor and a fake shell
// (shell scripts) and the fake logind. Checks what a shell sees: the connection, the state, what
// the system offers, the children, a refused power off and the logout.

#include "Session.h"
#include "SessionChildrenModel.h"

#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace MaiaSession;

namespace {

const char *compositorScript = R"(#!/bin/sh
READY="$1"
trap 'exit 0' TERM
WAYLAND_DISPLAY=wayland-test DISPLAY=:42 sh -c "$READY"
while :; do sleep 0.05; done
)";

const char *shellScript = R"(#!/bin/sh
trap 'exit 0' TERM
while :; do sleep 0.05; done
)";

void writeFile(const QString &path, const QByteArray &content)
{
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(content);
}

} // namespace

class TestSession : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void sessionAsTheShellSeesIt();
    void cleanupTestCase();

private:
    // /tmp, short: AF_UNIX paths are limited to about 108 bytes
    QTemporaryDir m_dir{QStringLiteral("/tmp/mss-XXXXXX")};
    QProcess m_service;
};

void TestSession::initTestCase()
{
    QVERIFY(m_dir.isValid());
    const QString dir = m_dir.path();
    writeFile(dir + QStringLiteral("/compositor.sh"), compositorScript);
    writeFile(dir + QStringLiteral("/shell.sh"), shellScript);
    writeFile(dir + QStringLiteral("/session.toml"),
              QStringLiteral("version = 1\n"
                             "[compositor.fake]\ncommand = [\"sh\", \"%1/compositor.sh\"]\nready = \"argument\"\n"
                             "[[process]]\nname = \"appMaiaServer\"\nkind = \"shell\"\n"
                             "command = [\"sh\", \"%1/shell.sh\"]\nrestart = \"always\"\n")
                  .arg(dir)
                  .toUtf8());

    // Before the first Session: the connection of the process reads it once
    const QString socket = dir + QStringLiteral("/s.sock");
    qputenv("MAIA_SESSION_SOCKET", socket.toUtf8());

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("MAIA_SESSION_MANIFEST"), dir + QStringLiteral("/session.toml"));
    env.insert(QStringLiteral("MAIA_SESSION_SOCKET"), socket);
    env.insert(QStringLiteral("MAIA_SESSION_BACKEND"), QStringLiteral("fake"));
    // Every power action fails, as when the user cancels the administrator's password
    env.insert(QStringLiteral("MAIA_SESSION_FAKE_LOGIND"), QStringLiteral("deny"));
    env.insert(QStringLiteral("MAIA_SESSION_TEST"), QStringLiteral("1"));
    env.insert(QStringLiteral("DBUS_SESSION_BUS_ADDRESS"), QStringLiteral("unix:path=/nonexistent"));
    env.insert(QStringLiteral("DBUS_SYSTEM_BUS_ADDRESS"), QStringLiteral("unix:path=/nonexistent"));
    m_service.setProcessEnvironment(env);
    m_service.setProcessChannelMode(QProcess::ForwardedErrorChannel);
    m_service.start(QStringLiteral(MAIA_SESSION_SERVICE), {QStringLiteral("--compositor"), QStringLiteral("fake")});
    QVERIFY(m_service.waitForStarted());
}

void TestSession::sessionAsTheShellSeesIt()
{
    Session session;
    SessionChildrenModel children;

    QTRY_VERIFY_WITH_TIMEOUT(session.connected(), 10000);
    QTRY_COMPARE_WITH_TIMEOUT(session.state(), Session::Running, 10000);
    QVERIFY(session.canLogout());
    QVERIFY(session.canPowerOff() && session.canReboot() && session.canSuspend());
    QVERIFY(!session.powerOffNeedsAuthorization());

    // The compositor and the shell
    QTRY_COMPARE_WITH_TIMEOUT(children.rowCount(), 2, 5000);
    const QModelIndex shell = children.index(1);
    QCOMPARE(shell.data(SessionChildrenModel::NameRole).toString(), QStringLiteral("appMaiaServer"));
    QTRY_COMPARE_WITH_TIMEOUT(children.index(1).data(SessionChildrenModel::StateRole).toString(), QStringLiteral("running"), 5000);
    QCOMPARE(children.index(0).data(SessionChildrenModel::KindRole).toString(), QStringLiteral("compositor"));

    // A refused power off: actionFailed, and the session goes on
    QSignalSpy failed(&session, &Session::actionFailed);
    session.powerOff();
    QTRY_COMPARE_WITH_TIMEOUT(failed.count(), 1, 5000);
    QCOMPARE(failed.at(0).at(0).toString(), QStringLiteral("powerOff"));
    QCOMPARE(failed.at(0).at(1).value<Session::Error>(), Session::NotAllowed);
    QCOMPARE(session.state(), Session::Running);

    // A restart by hand
    const uint pidBefore = children.index(1).data(SessionChildrenModel::PidRole).toUInt();
    children.restart(QStringLiteral("appMaiaServer"));
    QTRY_VERIFY_WITH_TIMEOUT(children.index(1).data(SessionChildrenModel::PidRole).toUInt() != pidBefore
                                 && children.index(1).data(SessionChildrenModel::PidRole).toUInt() != 0,
                             10000);
    QCOMPARE(children.index(1).data(SessionChildrenModel::RestartsRole).toUInt(), 1u);

    // The logout ends the session, and with it the service
    session.logout();
    QTRY_COMPARE_WITH_TIMEOUT(session.state(), Session::Ending, 5000);
    QCOMPARE(session.endingAction(), Session::Logout);
    QVERIFY(session.endingByUser());
    QVERIFY(m_service.waitForFinished(10000));
    QCOMPARE(m_service.exitCode(), 0);
    QTRY_VERIFY_WITH_TIMEOUT(!session.connected(), 5000);
}

void TestSession::cleanupTestCase()
{
    if (m_service.state() != QProcess::NotRunning) {
        m_service.kill();
        m_service.waitForFinished();
    }
}

QTEST_GUILESS_MAIN(TestSession)
#include "tst_session.moc"
