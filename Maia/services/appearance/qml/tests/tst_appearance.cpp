// The QML types of Maia.Appearance on a source filled by the test (no service, no Cap'n Proto)

#include "AppearanceSource.h"
#include "FrontendLook.h"
#include "WindowDecorations.h"

#include <QAbstractItemModelTester>
#include <QJSEngine>
#include <QSignalSpy>
#include <QTest>

using namespace MaiaAppearance;

class FakeSource : public AppearanceSource
{
public:
    QStringList commands;

    void setTheme(const QString &id, Callback done) override
    {
        commands.append(QStringLiteral("set ") + id);
        if (done)
            done(Result{});
    }
    void setBorderSize(Appearance::BorderSize size, Callback done) override
    {
        commands.append(QStringLiteral("border %1").arg(int(size)));
        if (done)
            done(Result{});
    }
    void install(const QString &path, IdCallback done) override
    {
        commands.append(QStringLiteral("install ") + path);
        if (done)
            done(Result{}, QStringLiteral("aurorae-svg:Glass"));
    }
    void remove(const QString &id, Callback done) override
    {
        commands.append(QStringLiteral("remove ") + id);
        if (done)
            done(Result{Appearance::ErrorCode::NotAllowed, QStringLiteral("in use")});
    }
    void refresh() override { commands.append(QStringLiteral("refresh")); }
    void activateFrontend(int, const QString &frontend, const QString &defaultThemeId) override
    {
        commands.append(QStringLiteral("activate ") + frontend + QLatin1Char(' ') + defaultThemeId);
    }
    void deactivateFrontend(int) override { commands.append(QStringLiteral("deactivate")); }
};

namespace {

ThemeData theme(const QString &id, const QString &name, Appearance::Origin origin = Appearance::Origin::System, bool available = true)
{
    ThemeData t;
    t.id = id;
    t.name = name;
    t.origin = origin;
    t.available = available;
    t.engine = id.startsWith(QLatin1String("aurorae-svg")) ? Appearance::Engine::AuroraeSvg : Appearance::Engine::Kdecoration;
    return t;
}

} // namespace

class TestAppearance : public QObject
{
    Q_OBJECT

    FakeSource *source = nullptr;

private Q_SLOTS:
    void init()
    {
        source = new FakeSource;
        AppearanceSource::setInstance(source);
        source->applyThemes({theme(QStringLiteral("kdecoration:org.kde.breeze"), QStringLiteral("Breeze")),
                             theme(QStringLiteral("aurorae-svg:Glass"), QStringLiteral("Glass"), Appearance::Origin::User),
                             theme(QStringLiteral("aurorae-qml:plastik"), QStringLiteral("Plastik"), Appearance::Origin::System, false)});
        source->applyCurrent(CurrentData{QStringLiteral("aurorae-svg:Glass"), Appearance::BorderSize::Theme, true, QString()});
        source->setConnected(true);
    }

    void cleanup()
    {
        AppearanceSource::setInstance(nullptr);
        delete source;
    }

    void themesAndTheChoice()
    {
        WindowDecorations model;
        QAbstractItemModelTester tester(&model);
        QCOMPARE(model.rowCount(), 3);
        QCOMPARE(model.currentThemeId(), QStringLiteral("aurorae-svg:Glass"));
        QCOMPARE(model.currentName(), QStringLiteral("Glass"));
        QVERIFY(model.confirmed());
        const auto glass = model.get(QStringLiteral("aurorae-svg:Glass"));
        QCOMPARE(glass.value(QStringLiteral("current")).toBool(), true);
        QCOMPARE(glass.value(QStringLiteral("removable")).toBool(), false); // in use
        QCOMPARE(model.get(QStringLiteral("aurorae-qml:plastik")).value(QStringLiteral("available")).toBool(), false);

        QSignalSpy changed(&model, &QAbstractItemModel::dataChanged);
        source->applyCurrent(CurrentData{QStringLiteral("kdecoration:org.kde.breeze"), Appearance::BorderSize::Large, false, QStringLiteral("Lumen")});
        QCOMPARE(changed.count(), 2); // the old and the new current row
        QCOMPARE(model.get(QStringLiteral("aurorae-svg:Glass")).value(QStringLiteral("removable")).toBool(), true);
        QCOMPARE(model.frontend(), QStringLiteral("Lumen"));
        QCOMPARE(model.borderSize(), Appearance::BorderSize::Large);

        QSignalSpy count(&model, &WindowDecorations::countChanged);
        source->applyThemes({theme(QStringLiteral("kdecoration:org.kde.breeze"), QStringLiteral("Breeze"))});
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(count.count(), 1);

        source->setConnected(false);
        QCOMPARE(model.rowCount(), 0);
        QVERIFY(!model.available());
    }

    void commandsCallBack()
    {
        QJSEngine engine;
        auto *model = new WindowDecorations;
        engine.newQObject(model); // owned by the engine, which calls the callbacks
        QJSValue got = engine.newObject();
        engine.globalObject().setProperty(QStringLiteral("got"), got);
        model->setTheme(QStringLiteral("kdecoration:org.kde.breeze"), engine.evaluate(QStringLiteral("(function (r) { got.set = r.ok })")));
        model->install(QStringLiteral("file:///tmp/Glass.tar.gz"), engine.evaluate(QStringLiteral("(function (r, id) { got.id = id })")));
        model->remove(QStringLiteral("aurorae-svg:Glass"), engine.evaluate(QStringLiteral("(function (r) { got.removeError = r.error })")));
        QCOMPARE(got.property(QStringLiteral("set")).toBool(), true);
        QCOMPARE(got.property(QStringLiteral("id")).toString(), QStringLiteral("aurorae-svg:Glass"));
        QCOMPARE(got.property(QStringLiteral("removeError")).toInt(), int(Appearance::ErrorCode::NotAllowed));
        QCOMPARE(source->commands,
                 QStringList({QStringLiteral("set kdecoration:org.kde.breeze"), QStringLiteral("install /tmp/Glass.tar.gz"),
                              QStringLiteral("remove aurorae-svg:Glass")}));
    }

    void aFrontendIsActiveWhileItsLookExists()
    {
        {
            FrontendLook look;
            look.classBegin();
            look.setFrontend(QStringLiteral("XPLuna"));
            look.setWindowDecoration(QStringLiteral("aurorae-svg:XBoomer"));
            QVERIFY(source->commands.isEmpty()); // not before the component is complete
            look.componentComplete();
            QCOMPARE(source->commands, QStringList{QStringLiteral("activate XPLuna aurorae-svg:XBoomer")});
        }
        QCOMPARE(source->commands.last(), QStringLiteral("deactivate"));
    }
};

QTEST_MAIN(TestAppearance)
#include "tst_appearance.moc"
