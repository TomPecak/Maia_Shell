#pragma once

#include <qqml.h>
#include <QObject>
#include <QGuiApplication> //for xcb_connection_t

#include <NETWM> //for xcb_window_t

#include "capplications.h"

class MActivity : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString icon READ icon NOTIFY iconChanged)
    Q_PROPERTY(bool launchPad READ launchPad NOTIFY launchPadChanged)

public:
    explicit MActivity(QObject *parent = nullptr);

    bool launchPad() const;

    QString title() const;
    QString icon() const;

    Q_INVOKABLE void close();
    Q_INVOKABLE void minimize();
    Q_INVOKABLE void restore();
    Q_INVOKABLE void maximize();
    Q_INVOKABLE void toggleMaximize();
    Q_INVOKABLE void move();

    bool isAcceptableWindow(quint64 wid);

private slots:
    void onActiveWindowChanged();

    void clearTitle();
    void clearIcon();

signals:
    void titleChanged();
    void iconChanged();
    void launchPadChanged();

private:
    xcb_connection_t *x11Connection();
    xcb_window_t rootWindow();

private:
    CApplications *m_cApps;
    QString m_title;
    QString m_icon;
    QString m_windowClass;
    quint32 m_pid;

    bool m_launchPad;
};
