// Sounds with a fake player: what reaches the player (name, file, theme), muting, bursts, the theme
// of the desktop's settings. The real player is only loaded, never asked to play (no noise).

#include "CanberraPlayer.h"
#include "Sounds.h"

#include <QElapsedTimer>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace MaiaSounds;

class FakePlayer final : public SoundPlayer
{
public:
    QList<SoundRequest> played;

    void play(const SoundRequest &request) override { played.append(request); }
    bool isAvailable() const override { return true; }
};

class TestSounds : public QObject
{
    Q_OBJECT

private:
    FakePlayer m_player;
    QTemporaryDir m_config;

private Q_SLOTS:
    void initTestCase()
    {
        // The desktop's settings of the test, not of the user
        qputenv("XDG_CONFIG_HOME", m_config.path().toUtf8());
        Sounds::setPlayer(&m_player);
    }

    void init()
    {
        m_player.played.clear();
        QFile::remove(m_config.filePath(QStringLiteral("kdeglobals")));
    }

    void aNameIsPlayedInTheTheme()
    {
        Sounds sounds;
        QCOMPARE(sounds.theme(), QStringLiteral("ocean"));
        QVERIFY(sounds.available());
        sounds.play(QStringLiteral("message-new-instant"));
        QCOMPARE(m_player.played.size(), 1);
        QCOMPARE(m_player.played[0].eventName, QStringLiteral("message-new-instant"));
        QVERIFY(m_player.played[0].filePath.isEmpty());
        QCOMPARE(m_player.played[0].theme, QStringLiteral("ocean"));
    }

    void aFileUrlBecomesAPathAndOtherUrlsAreRefused()
    {
        Sounds sounds;
        sounds.play(QString(), QStringLiteral("file:///usr/share/sounds/My%20Ding.oga"));
        sounds.play(QString(), QStringLiteral("/usr/share/sounds/plain.oga"));
        sounds.play(QString(), QStringLiteral("https://example.org/ding.oga"));
        QCOMPARE(m_player.played.size(), 2);
        QCOMPARE(m_player.played[0].filePath, QStringLiteral("/usr/share/sounds/My Ding.oga"));
        QCOMPARE(m_player.played[1].filePath, QStringLiteral("/usr/share/sounds/plain.oga"));
    }

    void nothingWithoutASoundOrWhenMuted()
    {
        Sounds sounds;
        sounds.play(QString(), QString());
        QSignalSpy enabledChanged(&sounds, &Sounds::enabledChanged);
        sounds.setEnabled(false);
        QCOMPARE(enabledChanged.count(), 1);
        sounds.play(QStringLiteral("message-new-instant"));
        QVERIFY(m_player.played.isEmpty());
        sounds.setEnabled(true);
        sounds.play(QStringLiteral("message-new-instant"));
        QCOMPARE(m_player.played.size(), 1);
    }

    void aBurstOfTheSameSoundPlaysOnce()
    {
        Sounds sounds;
        for (int i = 0; i < 100; ++i)
            sounds.play(QStringLiteral("message-new-instant"));
        sounds.play(QStringLiteral("dialog-error"));
        QCOMPARE(m_player.played.size(), 2);
        QTest::qWait(Sounds::kRepeatGap + 20);
        sounds.play(QStringLiteral("message-new-instant"));
        QCOMPARE(m_player.played.size(), 3);
    }

    void theThemeComesFromTheDesktopsSettings()
    {
        QFile kdeglobals(m_config.filePath(QStringLiteral("kdeglobals")));
        QVERIFY(kdeglobals.open(QIODevice::WriteOnly));
        kdeglobals.write("[General]\nColorScheme=BreezeDark\n\n[Sounds]\nTheme=freedesktop\n");
        kdeglobals.close();
        Sounds sounds;
        QCOMPARE(sounds.theme(), QStringLiteral("freedesktop"));
        QSignalSpy themeChanged(&sounds, &Sounds::themeChanged);
        sounds.setTheme(QStringLiteral("Yaru"));
        QCOMPARE(themeChanged.count(), 1);
        sounds.play(QStringLiteral("bell"));
        QCOMPARE(m_player.played.last().theme, QStringLiteral("Yaru"));
        // Empty: back to the settings' theme
        sounds.setTheme(QString());
        QCOMPARE(sounds.theme(), QStringLiteral("freedesktop"));
    }

    void theRealPlayerLoadsInTheBackground()
    {
        // Only loaded: nothing is played
        QElapsedTimer timer;
        timer.start();
        CanberraPlayer player;
        const qint64 constructing = timer.elapsed();
        QVERIFY2(constructing < 50, qPrintable(QString::number(constructing)));
        if (!QFile::exists(QStringLiteral("/usr/lib/x86_64-linux-gnu/libcanberra.so.0")) && !QFile::exists(QStringLiteral("/usr/lib/libcanberra.so.0")))
            QSKIP("no libcanberra on this machine");
        QTRY_VERIFY_WITH_TIMEOUT(player.isAvailable(), 5000);
    }
};

QTEST_MAIN(TestSounds)
#include "tst_sounds.moc"
