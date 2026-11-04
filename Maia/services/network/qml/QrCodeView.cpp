#include "QrCodeView.h"

#include <QPainter>
#include <QQuickWindow>

#include <cmath>

namespace MaiaNetwork {

QrCodeView::QrCodeView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(false);
}

void QrCodeView::changedSomething()
{
    update();
    Q_EMIT changed();
}

void QrCodeView::setModules(const QByteArray &modules)
{
    if (m_modules != modules) {
        m_modules = modules;
        changedSomething();
    }
}

void QrCodeView::setModuleCount(int count)
{
    if (m_count != count) {
        m_count = count;
        changedSomething();
    }
}

void QrCodeView::setColor(const QColor &color)
{
    if (m_color != color) {
        m_color = color;
        changedSomething();
    }
}

void QrCodeView::setBackground(const QColor &color)
{
    if (m_background != color) {
        m_background = color;
        changedSomething();
    }
}

void QrCodeView::setQuietZone(int modules)
{
    modules = qMax(0, modules);
    if (m_quietZone != modules) {
        m_quietZone = modules;
        changedSomething();
    }
}

void QrCodeView::paint(QPainter *painter)
{
    const qreal side = qMin(width(), height());
    painter->fillRect(QRectF((width() - side) / 2, (height() - side) / 2, side, side), m_background);
    if (m_count <= 0 || m_modules.size() < qsizetype(m_count) * m_count)
        return;
    const int total = m_count + 2 * m_quietZone;
    // Whole device pixels per module when there is room for at least one
    const qreal dpr = window() ? window()->effectiveDevicePixelRatio() : 1.0;
    qreal unit = side / total;
    if (unit * dpr >= 1)
        unit = std::floor(unit * dpr) / dpr;
    const qreal origin = std::round(((width() - unit * m_count) / 2) * dpr) / dpr;
    const qreal top = std::round(((height() - unit * m_count) / 2) * dpr) / dpr;
    const char *data = m_modules.constData();
    for (int y = 0; y < m_count; ++y) {
        // Runs of dark modules in a row as one rectangle
        int x = 0;
        while (x < m_count) {
            if (!data[y * m_count + x]) {
                ++x;
                continue;
            }
            const int start = x;
            while (x < m_count && data[y * m_count + x])
                ++x;
            painter->fillRect(QRectF(origin + start * unit, top + y * unit, (x - start) * unit, unit), m_color);
        }
    }
}

} // namespace MaiaNetwork
