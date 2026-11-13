#pragma once

// Event sounds through libcanberra, the library KDE (KNotification, Plasma) and GNOME use: a name
// of the freedesktop sound theme is looked up in the theme and its fallbacks, and the sample is
// cached by the sound server (PipeWire, PulseAudio), so a repeated sound costs nothing. Played with
// the role "event", so the mixer's notification sounds volume applies.
//
// The library is loaded at run time (dlopen), no development files are needed to build Maia;
// without it there is no sound and one warning. Everything runs in a thread of its own: the GUI
// thread only queues a request, even the first connection to the sound server is not its wait.

#include "SoundPlayer.h"

#include <QThread>

#include <atomic>

namespace MaiaSounds {

class CanberraWorker;

class CanberraPlayer final : public SoundPlayer
{
    Q_OBJECT

public:
    explicit CanberraPlayer(QObject *parent = nullptr);
    ~CanberraPlayer() override;

    void play(const SoundRequest &request) override;
    bool isAvailable() const override { return m_available; }

private:
    QThread m_thread;
    CanberraWorker *m_worker;
    std::atomic<bool> m_available{false};
};

} // namespace MaiaSounds
