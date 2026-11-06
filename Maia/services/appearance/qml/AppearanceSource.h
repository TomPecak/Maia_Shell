#pragma once

// The appearance state of a process, in the GUI thread, and the commands it can send.
//
// AppearanceConnection fills it from the service (the only source in production); tests fill it
// directly (tests/tst_appearance.cpp). The QML types (WindowDecorations, FrontendLook) only read
// it and call its commands, so they never see Cap'n Proto or threads.
//
// Every command takes an optional callback, called in the GUI thread with the service's result
// (also when the service is not there: Appearance.ErrorCode.Unavailable).

#include "AppearanceTypes.h"

#include <QObject>
#include <functional>

namespace MaiaAppearance {

class AppearanceSource : public QObject
{
    Q_OBJECT

public:
    using Callback = std::function<void(const Result &)>;
    using IdCallback = std::function<void(const Result &, const QString &)>;

    explicit AppearanceSource(QObject *parent = nullptr);

    // The process's source (the connection to the service), created on first use; a test sets its own
    static AppearanceSource *instance();
    static void setInstance(AppearanceSource *source);

    bool isConnected() const { return m_connected; }
    const CapabilitiesData &capabilities() const { return m_capabilities; }
    const QList<ThemeData> &themes() const { return m_themes; }
    const CurrentData &current() const { return m_current; }
    const ThemeData *theme(const QString &id) const;

    // --- Filling (GUI thread) ---

    void setConnected(bool connected);
    void applyCapabilities(const CapabilitiesData &capabilities);
    void applyThemes(const QList<ThemeData> &themes);
    void applyCurrent(const CurrentData &current);

    // --- Commands ---

    virtual void setTheme(const QString &id, Callback done = {}) = 0;
    virtual void setBorderSize(Appearance::BorderSize size, Callback done = {}) = 0;
    virtual void install(const QString &path, IdCallback done = {}) = 0;
    virtual void remove(const QString &id, Callback done = {}) = 0;
    virtual void refresh() = 0;
    // A frontend's shell runs (FrontendLook); kept, and renewed after a reconnection, until
    // deactivateFrontend(handle)
    virtual void activateFrontend(int handle, const QString &frontend, const QString &defaultThemeId) = 0;
    virtual void deactivateFrontend(int handle) = 0;

Q_SIGNALS:
    void connectedChanged();
    void capabilitiesChanged();
    void themesChanged();
    void currentChanged();

protected:
    // For commands while the service is not there
    static Result unavailable();

private:
    bool m_connected = false;
    CapabilitiesData m_capabilities;
    QList<ThemeData> m_themes;
    CurrentData m_current;
};

} // namespace MaiaAppearance
