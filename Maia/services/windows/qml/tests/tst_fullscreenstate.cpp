// FullscreenState on a fake window source: which window counts as "the user works fullscreen",
// on which screen, and that window drags do not make noise.

#include "FullscreenState.h"

#include <QGuiApplication>
#include <QScreen>
#include <QSignalSpy>
#include <QTest>

using namespace MaiaWindows;

// A window source the test feeds by hand
class FakeSource final : public WindowSource
{
public:
    FakeSource() { setConnected(true); }

    using WindowSource::applySnapshot;
    using WindowSource::remove;
    using WindowSource::upsert;

    void activate(const QString &) override { }
    void close(const QString &) override { }
    void setState(const QString &, State, bool) override { }
    void requestMove(const QString &) override { }
    void requestResize(const QString &) override { }
    void launchNewInstance(const QString &) override { }
    void launch(const QString &) override { }

protected:
    void fetchIcon(const QString &, quint32) override { }
};

namespace {

WindowInfo window(const QString &id, const QString &app, quint32 states, QRect geometry, qint64 lastActivated = 0)
{
    WindowInfo w;
    w.id = id;
    w.title = id;
    w.appId = app + QStringLiteral(".desktop");
    w.appName = app;
    w.states = states;
    w.geometry = geometry;
    w.lastActivated = lastActivated;
    return w;
}

} // namespace

class TestFullscreenState : public QObject
{
    Q_OBJECT

private:
    QRect screenArea() const { return QGuiApplication::primaryScreen()->geometry(); }

private Q_SLOTS:
    void nothingIsFullscreenWithoutWindows()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        QVERIFY(!state.active());
        QVERIFY(state.appName().isEmpty());
    }

    void theActiveFullscreenWindowCounts()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        QSignalSpy changed(&state, &FullscreenState::changed);
        source.upsert(window(QStringLiteral("editor"), QStringLiteral("kate"), Active, screenArea().adjusted(10, 10, -10, -10), 1));
        QVERIFY(!state.active());
        QCOMPARE(changed.count(), 0);

        source.upsert(window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen, screenArea(), 2));
        source.upsert(window(QStringLiteral("editor"), QStringLiteral("kate"), 0, screenArea().adjusted(10, 10, -10, -10), 1));
        QVERIFY(state.active());
        QCOMPARE(state.windowId(), QStringLiteral("film"));
        QCOMPARE(state.appName(), QStringLiteral("vlc"));
        QCOMPARE(state.appId(), QStringLiteral("vlc.desktop"));
        QCOMPARE(changed.count(), 1);
    }

    void aFullscreenWindowInTheBackgroundDoesNotCount()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        source.upsert(window(QStringLiteral("film"), QStringLiteral("vlc"), Fullscreen, screenArea(), 1));
        source.upsert(window(QStringLiteral("editor"), QStringLiteral("kate"), Active, screenArea(), 2));
        QVERIFY(!state.active());
        // Minimized while fullscreen: no film to watch
        source.upsert(window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen | Minimized, screenArea(), 3));
        source.upsert(window(QStringLiteral("editor"), QStringLiteral("kate"), 0, screenArea(), 2));
        QVERIFY(!state.active());
    }

    void leavingFullscreenOrClosingEndsIt()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        source.upsert(window(QStringLiteral("game"), QStringLiteral("supertux"), Active | Fullscreen, screenArea(), 1));
        QVERIFY(state.active());
        source.upsert(window(QStringLiteral("game"), QStringLiteral("supertux"), Active, screenArea(), 1));
        QVERIFY(!state.active());
        source.upsert(window(QStringLiteral("game"), QStringLiteral("supertux"), Active | Fullscreen, screenArea(), 1));
        QVERIFY(state.active());
        source.remove(QStringLiteral("game"));
        QVERIFY(!state.active());
        QVERIFY(state.windowId().isEmpty());
    }

    void whenTwoAreActiveTheLastActivatedCounts()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        // Focus moving: the compositor reports the old and the new one active for a moment
        source.upsert(window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen, screenArea(), 1));
        source.upsert(window(QStringLiteral("chat"), QStringLiteral("telegram"), Active, screenArea(), 5));
        QVERIFY(!state.active());
    }

    void onlyTheGivenScreenCounts()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        QSignalSpy screenChanged(&state, &FullscreenState::screenChanged);
        state.setScreen(QGuiApplication::primaryScreen());
        QCOMPARE(screenChanged.count(), 1);
        // On another monitor, right of this one
        const QRect other = screenArea().translated(screenArea().width(), 0);
        source.upsert(window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen, other, 1));
        QVERIFY(!state.active());
        // Without a screen, any screen counts
        state.setScreen(nullptr);
        QVERIFY(state.active());
        state.setScreen(QGuiApplication::primaryScreen());
        QVERIFY(!state.active());
        source.upsert(window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen, screenArea(), 1));
        QVERIFY(state.active());
    }

    void otherChangesOfWindowsMakeNoNoise()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        source.upsert(window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen, screenArea(), 1));
        source.upsert(window(QStringLiteral("editor"), QStringLiteral("kate"), 0, QRect(0, 0, 300, 200)));
        QSignalSpy changed(&state, &FullscreenState::changed);
        // Another window dragged, the film's title changing (a new episode)
        for (int x = 0; x < 50; ++x)
            source.upsert(window(QStringLiteral("editor"), QStringLiteral("kate"), 0, QRect(x, 0, 300, 200)));
        WindowInfo film = window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen, screenArea(), 1);
        film.title = QStringLiteral("Episode 2");
        source.upsert(film);
        QCOMPARE(changed.count(), 0);
        QVERIFY(state.active());
    }

    void aSnapshotAfterAReconnectionIsSeen()
    {
        FakeSource source;
        FullscreenState state(&source, nullptr);
        source.applySnapshot({window(QStringLiteral("film"), QStringLiteral("vlc"), Active | Fullscreen, screenArea(), 1)});
        QVERIFY(state.active());
        source.applySnapshot({});
        QVERIFY(!state.active());
    }
};

QTEST_MAIN(TestFullscreenState)
#include "tst_fullscreenstate.moc"
