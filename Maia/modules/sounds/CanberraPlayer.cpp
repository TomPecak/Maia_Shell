#include "CanberraPlayer.h"

#include <QDebug>
#include <QFile>
#include <QLoggingCategory>

#include <dlfcn.h>

// QT_LOGGING_RULES="maia.sounds.debug=true" shows every sound played
Q_LOGGING_CATEGORY(lcSounds, "maia.sounds", QtInfoMsg)

namespace MaiaSounds {

namespace {

// The parts of libcanberra's API that are used (canberra.h), resolved at run time
struct ca_context;
using CreateFn = int (*)(ca_context **);
using DestroyFn = int (*)(ca_context *);
using PlayFn = int (*)(ca_context *, uint32_t, ...);
using StrErrorFn = const char *(*)(int);
constexpr int kSuccess = 0;

} // namespace

// Lives in the player's thread
class CanberraWorker final : public QObject
{
public:
    explicit CanberraWorker(std::atomic<bool> *available)
        : m_available(available)
    {
    }

    ~CanberraWorker() override
    {
        if (m_context)
            m_destroy(m_context);
        if (m_library)
            dlclose(m_library);
    }

    // Loads the library and makes a context; false when there is none
    bool load()
    {
        if (m_context)
            return true;
        if (m_failed)
            return false;
        m_library = dlopen("libcanberra.so.0", RTLD_NOW | RTLD_LOCAL);
        if (m_library) {
            auto create = reinterpret_cast<CreateFn>(dlsym(m_library, "ca_context_create"));
            m_destroy = reinterpret_cast<DestroyFn>(dlsym(m_library, "ca_context_destroy"));
            m_play = reinterpret_cast<PlayFn>(dlsym(m_library, "ca_context_play"));
            m_strerror = reinterpret_cast<StrErrorFn>(dlsym(m_library, "ca_strerror"));
            if (create && m_destroy && m_play && m_strerror && create(&m_context) == kSuccess && m_context) {
                *m_available = true;
                return true;
            }
        }
        qCWarning(lcSounds) << "[Maia.Sounds] no libcanberra, event sounds are off:" << (m_library ? "unusable" : dlerror());
        m_failed = true;
        return false;
    }

    void play(const SoundRequest &request)
    {
        if (!load())
            return;
        const QByteArray name = request.eventName.toUtf8();
        const QByteArray file = QFile::encodeName(request.filePath);
        const QByteArray theme = request.theme.toUtf8();
        int result;
        // Properties as key/value pairs, ended by a null pointer; "volatile": the server may drop
        // the cached sample when it needs the memory
        if (!name.isEmpty() && !file.isEmpty()) {
            result = m_play(m_context, 0, "event.id", name.constData(), "media.filename", file.constData(),
                            "canberra.xdg-theme.name", theme.constData(), "media.role", "event",
                            "canberra.cache-control", "volatile", static_cast<const char *>(nullptr));
        } else if (!name.isEmpty()) {
            result = m_play(m_context, 0, "event.id", name.constData(), "canberra.xdg-theme.name", theme.constData(),
                            "media.role", "event", "canberra.cache-control", "volatile", static_cast<const char *>(nullptr));
        } else {
            result = m_play(m_context, 0, "media.filename", file.constData(), "media.role", "event",
                            "canberra.cache-control", "volatile", static_cast<const char *>(nullptr));
        }
        if (result != kSuccess)
            qCDebug(lcSounds) << "[Maia.Sounds] could not play" << request.eventName << request.filePath << ":" << m_strerror(result);
        else
            qCDebug(lcSounds) << "[Maia.Sounds] played" << request.eventName << request.filePath << "theme" << request.theme;
    }

private:
    std::atomic<bool> *m_available;
    void *m_library = nullptr;
    ca_context *m_context = nullptr;
    DestroyFn m_destroy = nullptr;
    PlayFn m_play = nullptr;
    StrErrorFn m_strerror = nullptr;
    bool m_failed = false;
};

CanberraPlayer::CanberraPlayer(QObject *parent)
    : SoundPlayer(parent)
    , m_worker(new CanberraWorker(&m_available))
{
    m_thread.setObjectName(QStringLiteral("Maia.Sounds"));
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    m_thread.start(QThread::LowPriority);
    // Loaded at once in the background: available is known before the first sound
    QMetaObject::invokeMethod(m_worker, [this] {
        if (m_worker->load())
            QMetaObject::invokeMethod(this, &SoundPlayer::availableChanged, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
}

CanberraPlayer::~CanberraPlayer()
{
    m_thread.quit();
    m_thread.wait();
}

void CanberraPlayer::play(const SoundRequest &request)
{
    QMetaObject::invokeMethod(m_worker, [worker = m_worker, request] { worker->play(request); }, Qt::QueuedConnection);
}

} // namespace MaiaSounds
