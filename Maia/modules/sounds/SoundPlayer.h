#pragma once

// What plays an event sound, behind Sounds. Today libcanberra (CanberraPlayer); later the request
// may go to a Maia audio service instead, without anything changing for the users of Sounds. The
// tests put a fake one in.

#include <QObject>
#include <QString>

namespace MaiaSounds {

struct SoundRequest {
    // A name of the sound theme ("message-new-instant"), or empty
    QString eventName;
    // A local file, or empty; with both, the file is played when the name has no sound
    QString filePath;
    // The sound theme the name is looked up in ("ocean"; its fallbacks, then "freedesktop")
    QString theme;
};

class SoundPlayer : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

    // Must not block: the caller is the GUI thread
    virtual void play(const SoundRequest &request) = 0;
    // Whether sounds can be played at all (false: the library or the sound server is missing)
    virtual bool isAvailable() const = 0;

Q_SIGNALS:
    void availableChanged();
};

} // namespace MaiaSounds
