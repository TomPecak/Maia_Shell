#include "MPreferredDevice.hpp"

#include <PulseAudioQt/Context>
#include <PulseAudioQt/Server>
#include <PulseAudioQt/Sink>
#include <PulseAudioQt/Source>

template<typename D>
[[nodiscard]] auto findPreferredDevice(QList<D *> devices, D *defaultDevice)
{
    // Only one device is the preferred one
    if (devices.count() == 1) {
        return devices.at(0);
    }

    auto lookForState = [&](PulseAudioQt::Device::State state) {
        D *ret = nullptr;
        for (const auto &device : devices) {
            if (device->state() != state || (device->isVirtualDevice() && !device->isDefault())) {
                continue;
            }
            if (!ret) {
                ret = device;
            } else if (device == defaultDevice) {
                ret = device;
                break;
            }
        }
        return ret;
    };

    D *preferred = nullptr;

    // Look for playing sinks + prefer default sink
    preferred = lookForState(PulseAudioQt::Device::RunningState);
    if (preferred) {
        return preferred;
    }

    // Look for idle sinks + prefer default sink
    preferred = lookForState(PulseAudioQt::Device::IdleState);
    if (preferred) {
        return preferred;
    }

    // Fallback to default sink
    return defaultDevice;
}

MPreferredDevice::MPreferredDevice(QObject *parent)
    : QObject(parent)
{
    connect(PulseAudioQt::Context::instance(),
            &PulseAudioQt::Context::sinkAdded,
            this,
            [this](PulseAudioQt::Sink *sink) {
                connect(sink,
                        &PulseAudioQt::Sink::stateChanged,
                        this,
                        &MPreferredDevice::updatePreferredSink,
                        Qt::UniqueConnection);
                updatePreferredSink();
            });
    connect(PulseAudioQt::Context::instance(),
            &PulseAudioQt::Context::sinkRemoved,
            this,
            &MPreferredDevice::updatePreferredSink);
    connect(PulseAudioQt::Context::instance()->server(),
            &PulseAudioQt::Server::defaultSinkChanged,
            this,
            &MPreferredDevice::updatePreferredSink);

    connect(PulseAudioQt::Context::instance(),
            &PulseAudioQt::Context::sourceAdded,
            this,
            [this](PulseAudioQt::Source *source) {
                connect(source,
                        &PulseAudioQt::Source::stateChanged,
                        this,
                        &MPreferredDevice::updatePreferredSource,
                        Qt::UniqueConnection);
                updatePreferredSource();
            });
    connect(PulseAudioQt::Context::instance(),
            &PulseAudioQt::Context::sourceRemoved,
            this,
            &MPreferredDevice::updatePreferredSource);
    connect(PulseAudioQt::Context::instance()->server(),
            &PulseAudioQt::Server::defaultSourceChanged,
            this,
            &MPreferredDevice::updatePreferredSource);
}

PulseAudioQt::Sink *MPreferredDevice::sink() const
{
    return m_sink;
}

PulseAudioQt::Source *MPreferredDevice::source() const
{
    return m_source;
}

void MPreferredDevice::updatePreferredSink()
{
    auto sink = findPreferredDevice(PulseAudioQt::Context::instance()->sinks(),
                                    PulseAudioQt::Context::instance()->server()->defaultSink());

    if (sink != m_sink) {
        //qDebug() << "Changing preferred sink to" << sink << (sink ? sink->name() : "");
        m_sink = sink;
        Q_EMIT sinkChanged();
    }
}

void MPreferredDevice::updatePreferredSource()
{
    auto source = findPreferredDevice(PulseAudioQt::Context::instance()->sources(),
                                      PulseAudioQt::Context::instance()->server()->defaultSource());

    if (source != m_source) {
        //qDebug() << "Changing preferred source to" << source << (source ? source->name() : "");
        m_source = source;
        Q_EMIT sourceChanged();
    }
}

#include "moc_MPreferredDevice.cpp"
