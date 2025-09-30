//This class if from KDE plasma-pa source code
//https://github.com/KDE/plasma-pa/blob/master/src/preferreddevice.h

#pragma once

#include <QObject>

#include <PulseAudioQt/Sink>
#include <PulseAudioQt/Source>

class MPreferredDevice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(PulseAudioQt::Sink *sink MEMBER m_sink NOTIFY sinkChanged)
    Q_PROPERTY(PulseAudioQt::Source *source MEMBER m_source NOTIFY sourceChanged)
public:
    explicit MPreferredDevice(QObject *parent = nullptr);
    [[nodiscard]] PulseAudioQt::Sink *sink() const;
    [[nodiscard]] PulseAudioQt::Source *source() const;

Q_SIGNALS:
    void sinkChanged();
    void sourceChanged();

private:
    void updatePreferredSink();
    void updatePreferredSource();
    [[nodiscard]] PulseAudioQt::Sink *findPreferredSink() const;
    PulseAudioQt::Sink *m_sink = nullptr;
    PulseAudioQt::Source *m_source = nullptr;
};
