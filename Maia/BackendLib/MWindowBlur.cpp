#include "MWindowBlur.hpp"

#include <QByteArray>
#include <QScopedPointer>
#include <QScopedPointerPodDeleter>
#include <QScreen>
#include <QPainterPath>

#ifndef USE_KDE_BLUR
#include <xcb/xcb.h>
#include <xcb/shape.h>
#include <xcb/xcb_icccm.h>
#endif

MWindowBlur::MWindowBlur(QObject *parent) noexcept
    : QObject(parent)
    , m_window(nullptr)
{

}

MWindowBlur::~MWindowBlur()
{

}

void MWindowBlur::classBegin()
{

}

void MWindowBlur::componentComplete()
{
    updateBlur();
}

void MWindowBlur::setWindow(QWindow *window)
{
    if(window != m_window){
        m_window = window;
        updateBlur();
        emit windowChanged();

        connect(m_window, &QWindow::visibleChanged, this, &MWindowBlur::onWindowVisibleChanged);
    }
}

QWindow *MWindowBlur::window()
{
    return m_window;
}

void MWindowBlur::setGeometry(const QRect &rect)
{
    if (rect != m_rect) {
        m_rect = rect;
        updateBlur();
        emit geometryChanged();
    }
}

QRect MWindowBlur::geometry() const
{
    return m_rect;
}

void MWindowBlur::setEnabled(bool enabled)
{
    if (enabled != m_enabled) {
        m_enabled = enabled;
        updateBlur();
        emit enabledChanged();
    }
}

bool MWindowBlur::enabled() const
{
    return m_enabled;
}



void MWindowBlur::setWindowRadius(qreal radius)
{
    if(radius != m_windowRadius){
        m_windowRadius = radius;
        updateBlur();
        emit windowRadiusChanged();
    }
}

qreal MWindowBlur::windowRadius() const
{
    return m_windowRadius;
}

void MWindowBlur::onWindowVisibleChanged(bool visible)
{
    if(visible){
        updateBlur();
    }
}

void MWindowBlur::updateBlur()
{
    if(!m_window)
        return;


#ifdef USE_KDE_BLUR
    // Use KDE's high-level API
    if (m_enabled) {
        // Compute region: full window with rounded corners (logical pixels).
        // Note: If you want to use m_rect for partial blur, replace with QRectF(m_rect).
        QPainterPath path;
        path.addRoundedRect(QRectF(QPointF(0, 0), m_window->size()), m_windowRadius, m_windowRadius);
        QRegion region = path.toFillPolygon().toPolygon();  // Logical pixels, as required by KWindowEffects
        KWindowEffects::enableBlurBehind(m_window, true, region);
    } else {
        KWindowEffects::enableBlurBehind(m_window, false);
    }
#else
    // Original XCB fallback
    xcb_connection_t *c = x11Connection();
    if (!c)
        return;

    const QByteArray effectName = QByteArrayLiteral("_KDE_NET_WM_BLUR_BEHIND_REGION");
    xcb_intern_atom_cookie_t atomCookie = xcb_intern_atom_unchecked(c, false, effectName.length(), effectName.constData());
    QScopedPointer<xcb_intern_atom_reply_t, QScopedPointerPodDeleter> atom(xcb_intern_atom_reply(c, atomCookie, nullptr));
    if (!atom)
        return;

    if (m_enabled) {
        qreal devicePixelRatio = m_window->screen()->devicePixelRatio();
        QPainterPath path;
        path.addRoundedRect(QRectF(QPoint(0, 0), m_window->size() * devicePixelRatio),
                            m_windowRadius * devicePixelRatio,
                            m_windowRadius * devicePixelRatio);
        QVector<uint32_t> data;
        foreach (const QPolygonF &polygon, path.toFillPolygons()) {
            QRegion region = polygon.toPolygon();
            for (auto i = region.begin(); i != region.end(); ++i) {
                data << i->x() << i->y() << i->width() << i->height();
            }
        }

        xcb_change_property(c, XCB_PROP_MODE_REPLACE, m_window->winId(), atom->atom, XCB_ATOM_CARDINAL,
                            32, data.size(), data.constData());

    } else {
        xcb_delete_property(c, m_window->winId(), atom->atom);
    }
#endif
}

#ifndef USE_KDE_BLUR
xcb_connection_t *MWindowBlur::x11Connection()
{
    auto *x11App = qApp->nativeInterface<QNativeInterface::QX11Application>();
    return x11App ? x11App->connection() : nullptr;
}
#endif

