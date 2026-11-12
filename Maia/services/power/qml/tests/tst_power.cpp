// Maia.Power against the real power service with its fake backend (a simulated laptop: a battery
// at 80 % on battery, a mouse, a panel at 50 %, a keyboard backlight with 3 levels, three profiles).
// Checks what a shell sees and does: the battery, the slider of the brightness, the keyboard, the
// profile, a profile hold, the models, and a refused request.

#include "BatteriesModel.h"
#include "DisplaysModel.h"
#include "Power.h"
#include "ProfileHold.h"

#include <QProcess>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace MaiaPower;

class TestPower : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void theBattery();
    void theBrightnessSlider();
    void theKeyboard();
    void profilesAndHolds();
    void theModels();
    void aFailedRequestIsReported();
    void cleanupTestCase();

private:
    // /tmp, short: AF_UNIX paths are limited to about 108 bytes
    QTemporaryDir m_dir{QStringLiteral("/tmp/mps-XXXXXX")};
    QProcess m_service;
};

void TestPower::initTestCase()
{
    QVERIFY(m_dir.isValid());
    const QString socket = m_dir.path() + QStringLiteral("/p.sock");
    // Before the first object of the module: the connection reads it once
    qputenv("MAIA_POWER_SOCKET", socket.toUtf8());
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("MAIA_POWER_SOCKET"), socket);
    env.insert(QStringLiteral("MAIA_POWER_BACKEND"), QStringLiteral("fake"));
    m_service.setProcessEnvironment(env);
    m_service.setProcessChannelMode(QProcess::ForwardedErrorChannel);
    m_service.start(QStringLiteral(MAIA_POWER_SERVICE), {});
    QVERIFY(m_service.waitForStarted());
}

void TestPower::theBattery()
{
    Power power;
    QTRY_VERIFY_WITH_TIMEOUT(power.connected(), 10000);
    QVERIFY(power.upowerAvailable());
    QVERIFY(power.hasBattery());
    QVERIFY(power.onBattery());
    QVERIFY(!power.pluggedIn());
    QCOMPARE(power.batteryPercentage(), 80.0);
    QCOMPARE(power.batteryState(), Power::Discharging);
    QVERIFY(!power.charging());
    QCOMPARE(power.warningLevel(), Power::NoWarning);
    QVERIFY(power.timeToEmpty() > 0);
    QCOMPARE(power.batteryIconName(), QStringLiteral("battery-level-80-symbolic"));
    QVERIFY(power.lidPresent() && !power.lidClosed());
}

void TestPower::theBrightnessSlider()
{
    Power power;
    QTRY_VERIFY_WITH_TIMEOUT(power.brightnessAvailable(), 10000);
    QCOMPARE(power.brightness(), 0.5);
    QVERIFY(power.brightnessMinimum() > 0.0);

    // Dragged: every value shows at once, the slider never jumps back to an older echo
    QList<double> shown;
    connect(&power, &Power::brightnessChanged, this, [&] { shown.append(power.brightness()); });
    for (int i = 1; i <= 10; ++i) {
        const double value = 0.5 + i * 0.04;
        shown.clear();
        power.setBrightness(value);
        QTest::qWait(10);
        // Echoes of the service came meanwhile; the slider still shows what the user set
        for (double seen : shown)
            QCOMPARE(seen, value);
        QCOMPARE(power.brightness(), value);
    }
    // The screen ends where the slider was left
    QTRY_COMPARE_WITH_TIMEOUT(power.brightness(), 0.9, 3000);
    QTest::qWait(600);
    QCOMPARE(power.brightness(), 0.9);

    // Never off
    power.setBrightness(0.0);
    QCOMPARE(power.brightness(), power.brightnessMinimum());

    // The keys
    power.setBrightness(0.5);
    QTest::qWait(600);
    power.stepBrightness(2);
    QTRY_COMPARE_WITH_TIMEOUT(power.brightness(), 0.6, 3000);
}

void TestPower::theKeyboard()
{
    Power power;
    QTRY_VERIFY_WITH_TIMEOUT(power.keyboardBrightnessAvailable(), 10000);
    QCOMPARE(power.keyboardBrightnessSteps(), 2);
    QCOMPARE(power.keyboardBrightness(), 0.5);
    power.setKeyboardBrightness(1.0);
    QTRY_COMPARE_WITH_TIMEOUT(power.keyboardBrightness(), 1.0, 3000);
    power.setKeyboardBrightness(0.0);
    QTRY_COMPARE_WITH_TIMEOUT(power.keyboardBrightness(), 0.0, 3000);
}

void TestPower::profilesAndHolds()
{
    Power power;
    QTRY_VERIFY_WITH_TIMEOUT(power.profilesAvailable(), 10000);
    QCOMPARE(power.profiles().size(), 3);
    QCOMPARE(power.profile(), Power::Balanced);
    QCOMPARE(power.performanceDegraded(), Power::NotDegraded);

    power.setProfile(Power::PowerSaver);
    QTRY_COMPARE_WITH_TIMEOUT(power.profile(), Power::PowerSaver, 3000);

    {
        ProfileHold hold;
        hold.classBegin();
        hold.setProfile(Power::Performance);
        hold.setReason(QStringLiteral("Compiling"));
        hold.setApplicationId(QStringLiteral("org.maia.test"));
        hold.setActive(true);
        hold.componentComplete();
        QTRY_VERIFY_WITH_TIMEOUT(hold.held(), 3000);
        QTRY_COMPARE_WITH_TIMEOUT(power.profile(), Power::Performance, 3000);
        QCOMPARE(power.profileHolds().size(), 1);
        QCOMPARE(power.profileHolds().first().toMap().value(QStringLiteral("reason")).toString(), QStringLiteral("Compiling"));

        hold.setActive(false);
        QTRY_COMPARE_WITH_TIMEOUT(power.profile(), Power::PowerSaver, 3000);
        QVERIFY(!hold.held());
        hold.setActive(true);
        QTRY_COMPARE_WITH_TIMEOUT(power.profile(), Power::Performance, 3000);
        // Destroyed while held: released
    }
    QTRY_COMPARE_WITH_TIMEOUT(power.profile(), Power::PowerSaver, 3000);
    QTRY_VERIFY_WITH_TIMEOUT(power.profileHolds().isEmpty(), 3000);
    power.setProfile(Power::Balanced);
    QTRY_COMPARE_WITH_TIMEOUT(power.profile(), Power::Balanced, 3000);
}

void TestPower::theModels()
{
    BatteriesModel all;
    BatteriesModel devices;
    devices.setDevicesOnly(true);
    DisplaysModel displays;
    QTRY_COMPARE_WITH_TIMEOUT(all.rowCount(), 2, 10000);
    QCOMPARE(devices.rowCount(), 1);
    const QModelIndex mouse = devices.index(0);
    QCOMPARE(mouse.data(BatteriesModel::ModelNameRole).toString(), QStringLiteral("MX Master 3"));
    QCOMPARE(mouse.data(BatteriesModel::KindRole).toInt(), int(Power::MouseDevice));
    QCOMPARE(mouse.data(BatteriesModel::PercentageRole).toDouble(), 45.0);
    QCOMPARE(mouse.data(BatteriesModel::PowerSupplyRole).toBool(), false);

    QTRY_COMPARE_WITH_TIMEOUT(displays.rowCount(), 1, 10000);
    const QString id = displays.index(0).data(DisplaysModel::IdRole).toString();
    QCOMPARE(id, QStringLiteral("backlight:fake_backlight"));
    displays.setBrightness(id, 0.25);
    QTRY_COMPARE_WITH_TIMEOUT(displays.index(0).data(DisplaysModel::BrightnessRole).toDouble(), 0.25, 3000);
}

void TestPower::aFailedRequestIsReported()
{
    Power power;
    DisplaysModel displays;
    QTRY_VERIFY_WITH_TIMEOUT(power.connected(), 10000);
    QSignalSpy failed(&power, &Power::requestFailed);
    displays.setBrightness(QStringLiteral("backlight:nothing"), 0.5);
    QTRY_COMPARE_WITH_TIMEOUT(failed.count(), 1, 3000);
    QCOMPARE(failed.at(0).at(0).toString(), QStringLiteral("setBrightness"));
    QCOMPARE(failed.at(0).at(1).value<Power::Error>(), Power::NotFound);
    // Successful requests say nothing
    power.setKeyboardBrightness(0.5);
    QTest::qWait(200);
    QCOMPARE(failed.count(), 1);
}

void TestPower::cleanupTestCase()
{
    if (m_service.state() != QProcess::NotRunning) {
        m_service.terminate();
        m_service.waitForFinished(5000);
    }
}

QTEST_GUILESS_MAIN(TestPower)
#include "tst_power.moc"
