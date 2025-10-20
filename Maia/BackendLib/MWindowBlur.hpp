#pragma once

#include <QObject>
#include <qqml.h>
#include <QQmlParserStatus>
#include <QWindow>
#include <QRect>
#include <QGuiApplication> // for xcb_connection_t (if not using KDE)

#warning "KDE KWindowEffects blur implementation doesn't work"
//#define USE_KDE_BLUR 1

#ifdef USE_KDE_BLUR
#include <KWindowEffects>
#endif

class MWindowBlur : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QWindow *window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(QRect geometry READ geometry WRITE setGeometry NOTIFY geometryChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(qreal windowRadius READ windowRadius WRITE setWindowRadius NOTIFY windowRadiusChanged)
    Q_INTERFACES(QQmlParserStatus)

public:
    MWindowBlur(QObject *parent = nullptr) noexcept;
    ~MWindowBlur() override;

    void classBegin() override;
    void componentComplete() override;

    void setWindow(QWindow *window);
    QWindow *window();

    void setGeometry(const QRect &rect);
    QRect geometry() const;

    void setEnabled(bool enabled);
    bool enabled() const;

    void setWindowRadius(qreal radius);
    qreal windowRadius() const;

private slots:
    void onWindowVisibleChanged(bool);

private:
    void updateBlur();
#ifndef USE_KDE_BLUR
    xcb_connection_t *x11Connection();
#endif

signals:
    void windowChanged();
    void enabledChanged();
    void windowRadiusChanged();
    void geometryChanged();

private:
    QWindow *m_window;
    QRect m_rect;
    bool m_enabled;
    qreal m_windowRadius;
};
