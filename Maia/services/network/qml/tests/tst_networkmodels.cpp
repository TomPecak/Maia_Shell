// The QML types of Maia.Network on a fake source (no service, no Cap'n Proto): the order of the
// models, their row changes (QAbstractItemModelTester), WifiStatus, the password prompt.

#include "NetworkControl.h"
#include "NetworkSource.h"
#include "SavedNetworksModel.h"
#include "SecretPrompt.h"
#include "SettingsMap.h"
#include "WifiDevicesModel.h"
#include "WifiNetworksModel.h"
#include "WifiStatus.h"

#include <QAbstractItemModelTester>
#include <QJSEngine>
#include <QSignalSpy>
#include <QTest>

using namespace MaiaNetwork;

// Records the commands instead of sending them
class FakeSource : public NetworkSource
{
public:
    QStringList commands;
    ConnectionSettingsData stored;
    QList<QPair<QString, bool>> answers;
    bool prompterRegistered = false;

    void setWirelessEnabled(bool enabled, Callback done) override { record(QStringLiteral("wifi %1").arg(enabled), done); }
    void requestScan(const QString &id, Callback done) override { record(QStringLiteral("scan ") + id, done); }
    void connectNetwork(const QString &id, Callback done) override { record(QStringLiteral("connect ") + id, done); }
    void activate(const QString &uuid, const QString &, Callback done) override { record(QStringLiteral("activate ") + uuid, done); }
    void disconnectDevice(const QString &id, Callback done) override { record(QStringLiteral("disconnect ") + id, done); }
    void forget(const QString &uuid, Callback done) override { record(QStringLiteral("forget ") + uuid, done); }
    void checkConnectivity(Callback done) override { record(QStringLiteral("check"), done); }
    void connectWithSettings(const QString &, const ConnectionSettingsData &settings, const QList<SecretData> &, ValueCallback<QString> done) override
    {
        commands.append(QStringLiteral("connect settings ") + settings.name);
        if (done)
            done(Result{}, QStringLiteral("uuid-new"));
    }
    void settings(const QString &uuid, ValueCallback<ConnectionSettingsData> done) override
    {
        commands.append(QStringLiteral("settings ") + uuid);
        done(Result{}, stored);
    }
    void updateSettings(const QString &uuid, const ConnectionSettingsData &settings, const QList<SecretData> &, Callback done) override
    {
        stored = settings;
        record(QStringLiteral("update ") + uuid, done);
    }
    void secrets(const QString &uuid, ValueCallback<QList<SecretData>> done) override
    {
        commands.append(QStringLiteral("secrets ") + uuid);
        done(Result{}, {SecretData{Network::SecretKey::WifiPassword, QStringLiteral("secret")}});
    }
    void qrCode(const QString &uuid, ValueCallback<QrCodeData> done) override
    {
        commands.append(QStringLiteral("qr ") + uuid);
        done(Result{}, QrCodeData{QStringLiteral("WIFI:S:x;T:nopass;;"), 21, QByteArray(21 * 21, 1)});
    }
    void startHotspot(const QString &, const QString &ssid, const QString &password, ValueCallback<QString, QString> done) override
    {
        commands.append(QStringLiteral("hotspot ") + ssid);
        if (done)
            done(Result{}, QStringLiteral("uuid-hotspot"), password.isEmpty() ? QStringLiteral("abcd2345") : password);
    }
    void stopHotspot(const QString &, Callback done) override { record(QStringLiteral("stop hotspot"), done); }
    void setPrompterRegistered(bool registered) override { prompterRegistered = registered; }
    void answerSecrets(const QString &id, bool cancelled, const QList<SecretData> &secrets) override
    {
        answers.append({id + (secrets.isEmpty() ? QString() : QLatin1Char(':') + secrets.first().value), cancelled});
    }

private:
    void record(const QString &command, const Callback &done)
    {
        commands.append(command);
        if (done)
            done(Result{});
    }
};

namespace {

NetworkData network(const QString &name, int strength, Network::Security security, bool known = false, bool active = false)
{
    NetworkData n;
    n.id = QStringLiteral("wlan0/") + name;
    n.deviceId = QStringLiteral("wlan0");
    n.name = name;
    n.strength = strength;
    n.security = security;
    if (known)
        n.connectionUuids = {QStringLiteral("uuid-") + name};
    n.active = active;
    return n;
}

// QT_NO_CAST_FROM_ASCII: string lists from literals
QStringList list(std::initializer_list<const char *> items)
{
    QStringList out;
    for (const char *item : items)
        out.append(QString::fromUtf8(item));
    return out;
}

QStringList names(const QAbstractItemModel &model)
{
    QStringList out;
    for (int row = 0; row < model.rowCount(); ++row)
        out.append(model.data(model.index(row, 0)).toString());
    return out;
}

} // namespace

class TestNetworkModels : public QObject
{
    Q_OBJECT

private:
    FakeSource *source = nullptr;

    void fill()
    {
        StatusData status;
        status.running = true;
        status.wirelessEnabled = true;
        status.wirelessHardwareEnabled = true;
        status.permissions.enableDisableWifi = Network::Permission::Yes;
        DeviceData device;
        device.id = QStringLiteral("wlan0");
        device.state = Network::DeviceState::Connected;
        device.activeNetworkId = QStringLiteral("wlan0/Home");
        device.activeConnectionUuid = QStringLiteral("uuid-Home");
        ConnectionData home;
        home.uuid = QStringLiteral("uuid-Home");
        home.name = QStringLiteral("Home");
        home.lastUsed = 2000;
        home.activeDeviceId = QStringLiteral("wlan0");
        ConnectionData office;
        office.uuid = QStringLiteral("uuid-Office");
        office.name = QStringLiteral("Office");
        office.lastUsed = 3000;
        ConnectionData hotspot;
        hotspot.uuid = QStringLiteral("uuid-Hotspot");
        hotspot.name = QStringLiteral("Hotspot");
        hotspot.hotspot = true;
        source->applySnapshot(status,
                              {device},
                              {network(QStringLiteral("Cafe"), 90, Network::Security::None),
                               network(QStringLiteral("Home"), 40, Network::Security::WpaPersonal, true, true),
                               network(QStringLiteral("Office"), 30, Network::Security::WpaPersonal, true),
                               network(QStringLiteral("Lab"), 90, Network::Security::WpaPersonal),
                               network(QStringLiteral("Owe"), 90, Network::Security::EnhancedOpen)},
                              {home, office, hotspot});
        source->setConnected(true);
    }

private Q_SLOTS:
    void init()
    {
        source = new FakeSource;
        NetworkSource::setInstance(source);
        fill();
    }

    void cleanup()
    {
        NetworkSource::setInstance(nullptr);
        delete source;
    }

    void networksAreOrderedLikeGnome()
    {
        WifiNetworksModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        // active, then saved, then by strength; secured before open (Owe has no padlock), then by name
        QCOMPARE(names(model), list({"Home", "Office", "Lab", "Cafe", "Owe"}));
        QCOMPARE(model.data(model.index(0), WifiNetworksModel::SecureRole).toBool(), true);
        QCOMPARE(model.data(model.index(4), WifiNetworksModel::SecureRole).toBool(), false);
        QCOMPARE(model.data(model.index(2), WifiNetworksModel::SignalLevelRole).toInt(), 4);
    }

    void rowsMoveWhenTheOrderChanges()
    {
        WifiNetworksModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        QSignalSpy moved(&model, &QAbstractItemModel::rowsMoved);
        QSignalSpy reset(&model, &QAbstractItemModel::modelReset);
        source->upsertNetwork(network(QStringLiteral("Cafe"), 95, Network::Security::WpaPersonal));
        QCOMPARE(names(model), list({"Home", "Office", "Cafe", "Lab", "Owe"}));
        QVERIFY(moved.count() > 0);
        QCOMPARE(reset.count(), 0);
        source->removeNetwork(QStringLiteral("wlan0/Lab"));
        QCOMPARE(names(model), list({"Home", "Office", "Cafe", "Owe"}));
    }

    void theLimitKeepsTheFirstRows()
    {
        WifiNetworksModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        model.setLimit(2);
        QCOMPARE(names(model), list({"Home", "Office"}));
        model.setLimit(0);
        QCOMPARE(model.rowCount(), 5);
    }

    void connectingFollowsTheDevice()
    {
        WifiNetworksModel model;
        DeviceData device = *source->device(QStringLiteral("wlan0"));
        device.state = Network::DeviceState::NeedAuth;
        source->upsertDevice(device);
        QCOMPARE(model.data(model.index(0), WifiNetworksModel::ConnectingRole).toBool(), true);
        model.connectNetwork(QStringLiteral("wlan0/Lab"));
        QCOMPARE(source->commands.last(), QStringLiteral("connect wlan0/Lab"));
    }

    void savedNetworksLastUsedFirstWithoutHotspots()
    {
        SavedNetworksModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        QCOMPARE(names(model), list({"Office", "Home"}));
        QCOMPARE(model.data(model.index(1), SavedNetworksModel::ActiveRole).toBool(), true);
        QCOMPARE(model.data(model.index(0), SavedNetworksModel::InRangeRole).toBool(), true);
        source->removeNetwork(QStringLiteral("wlan0/Office"));
        QCOMPARE(model.data(model.index(0), SavedNetworksModel::InRangeRole).toBool(), false);
        model.forget(QStringLiteral("uuid-Office"));
        QCOMPARE(source->commands.last(), QStringLiteral("forget uuid-Office"));
    }

    void statusDescribesTheConnection()
    {
        WifiStatus status;
        QVERIFY(status.available());
        QVERIFY(status.enabled());
        QVERIFY(status.canToggle());
        QVERIFY(status.connected());
        QCOMPARE(status.networkName(), QStringLiteral("Home"));
        QCOMPARE(status.signalLevel(), 2);
        QSignalSpy changed(&status, &WifiStatus::changed);
        StatusData off = source->status();
        off.wirelessEnabled = false;
        source->applyStatus(off);
        QCOMPARE(changed.count(), 1);
        QVERIFY(!status.enabled());
        status.toggle();
        QCOMPARE(source->commands.last(), QStringLiteral("wifi 1"));
        source->setConnected(false);
        QVERIFY(!status.available());
        QVERIFY(!status.connected());
    }

    void devicesAreListed()
    {
        WifiDevicesModel model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::QtTest);
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(model.get(QStringLiteral("wlan0")).value(QStringLiteral("activeNetworkId")).toString(), QStringLiteral("wlan0/Home"));
    }

    void thePromptAnswersInOrder()
    {
        SecretPrompt prompt;
        QVERIFY(!source->prompterRegistered);
        prompt.setActive(true);
        QVERIFY(source->prompterRegistered);

        SecretRequestData first;
        first.id = QStringLiteral("r1");
        first.name = QStringLiteral("Lab");
        first.fields = {SecretFieldData{Network::SecretKey::WifiPassword, {}, true, Network::Validation::WpaPassword}};
        SecretRequestData second = first;
        second.id = QStringLiteral("r2");
        second.name = QStringLiteral("Other");
        source->applySecretRequest(first);
        source->applySecretRequest(second);
        QVERIFY(prompt.pending());
        QCOMPARE(prompt.name(), QStringLiteral("Lab"));
        QVERIFY(!prompt.valid(0, QStringLiteral("short")));
        QVERIFY(prompt.valid(0, QStringLiteral("long enough")));

        prompt.answer({QStringLiteral("long enough")});
        QCOMPARE(source->answers.last(), qMakePair(QStringLiteral("r1:long enough"), false));
        QCOMPARE(prompt.name(), QStringLiteral("Other"));
        source->applySecretCancel(QStringLiteral("r2"));
        QVERIFY(!prompt.pending());

        source->applySecretRequest(first);
        prompt.setActive(false);
        QCOMPARE(source->answers.last(), qMakePair(QStringLiteral("r1"), true));
        QVERIFY(!source->prompterRegistered);
    }

    void settingsSurviveJavaScript()
    {
        ConnectionSettingsData settings;
        settings.name = QStringLiteral("Lab");
        settings.wifi.ssid = QByteArray("Lab");
        settings.wifi.clonedMac = Network::ClonedMac::Random;
        settings.security.security = Network::Security::WpaEnterprise;
        settings.security.eap.method = Network::EapMethod::Ttls;
        settings.security.eap.innerAuth = Network::InnerAuth::Pap;
        settings.ip4.method = Network::IpMethod::Manual;
        settings.ip4.addresses = {IpAddressData{QStringLiteral("192.168.7.20"), 24}};
        settings.ip4.routes = {RouteData{QStringLiteral("10.0.0.0"), 8, QStringLiteral("192.168.7.254"), 50}};
        settings.ip4.dns = {QStringLiteral("1.1.1.1")};
        QCOMPARE(settingsFromMap(settingsToMap(settings)), settings);

        // Through a JavaScript object, as an editor changes it
        QJSEngine engine;
        QJSValue object = engine.toScriptValue(settingsToMap(settings));
        object.property(QStringLiteral("ip4")).setProperty(QStringLiteral("method"), int(Network::IpMethod::Auto));
        const auto edited = settingsFromMap(engine.fromScriptValue<QVariantMap>(object));
        QCOMPARE(edited.ip4.method, Network::IpMethod::Auto);
        QCOMPARE(edited.security.eap.innerAuth, Network::InnerAuth::Pap);
    }

    void ssidsThatAreNotUtf8AreKept()
    {
        ConnectionSettingsData settings;
        settings.wifi.ssid = QByteArray("caf\xe9", 4);
        QCOMPARE(settingsFromMap(settingsToMap(settings)).wifi.ssid, settings.wifi.ssid);
        auto map = settingsToMap(settings);
        auto wifi = map.value(QStringLiteral("wifi")).toMap();
        wifi.insert(QStringLiteral("ssid"), QStringLiteral("Cafe"));
        map.insert(QStringLiteral("wifi"), wifi);
        QCOMPARE(settingsFromMap(map).wifi.ssid, QByteArray("Cafe"));
    }

    void controlCallsBackWithValues()
    {
        QJSEngine engine;
        auto *control = new NetworkControl;
        engine.newQObject(control); // owned by the engine, which calls the callbacks
        QJSValue got = engine.newObject();
        engine.globalObject().setProperty(QStringLiteral("got"), got);
        control->startHotspot({}, QStringLiteral("maia"), {}, engine.evaluate(QStringLiteral("(function (r, v) { got.ok = r.ok; got.password = v.password })")));
        QCOMPARE(got.property(QStringLiteral("ok")).toBool(), true);
        QCOMPARE(got.property(QStringLiteral("password")).toString(), QStringLiteral("abcd2345"));
        control->qrCode(QStringLiteral("uuid-Home"), engine.evaluate(QStringLiteral("(function (r, v) { got.size = v.size })")));
        QCOMPARE(got.property(QStringLiteral("size")).toInt(), 21);
        const QVariantList secrets = {QVariantMap{{QStringLiteral("key"), int(Network::SecretKey::WifiPassword)}, {QStringLiteral("value"), QStringLiteral("x")}}};
        QCOMPARE(control->secretValue(secrets, int(Network::SecretKey::WifiPassword)), QStringLiteral("x"));
        QVERIFY(control->isValidAddress(QStringLiteral("192.168.1.1"), false));
        QVERIFY(!control->isValidAddress(QStringLiteral("192.168.1"), false));
        QVERIFY(control->isValidAddress(QStringLiteral("fe80::1"), true));
        QVERIFY(control->isValidMac(QStringLiteral("0a:00:00:00:00:01")));
        QVERIFY(!control->isValidMac(QStringLiteral("0a:00:00:00:00")));
    }

    void passwordChecks()
    {
        QVERIFY(!Network::accepts(Network::Validation::WpaPassword, QStringLiteral("1234567")));
        QVERIFY(Network::accepts(Network::Validation::WpaPassword, QStringLiteral("12345678")));
        QVERIFY(Network::accepts(Network::Validation::WpaPassword, QString(64, QLatin1Char('a'))));
        QVERIFY(!Network::accepts(Network::Validation::WpaPassword, QString(64, QLatin1Char('z'))));
        QVERIFY(Network::accepts(Network::Validation::WepKey, QStringLiteral("abcde")));
        QVERIFY(!Network::accepts(Network::Validation::WepKey, QStringLiteral("abcdef")));
    }
};

QTEST_MAIN(TestNetworkModels)
#include "tst_networkmodels.moc"
