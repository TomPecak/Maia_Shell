#include "MaskTracker.hpp"

MaskTracker *MaskTracker::forWindow(QQuickWindow *window)
{
    auto *mask = window->findChild<MaskTracker *>(QString(), Qt::FindDirectChildrenOnly);
    return mask ? mask : new MaskTracker(window);
}

MaskTracker::MaskTracker(QQuickWindow *window)
    : QObject(window)
    , m_window(window)
{
    // afterAnimating: GUI thread, once per rendered frame, before the frame is synchronized,
    // so the mask matches the frame that is about to be rendered
    connect(window, &QQuickWindow::afterAnimating, this, &MaskTracker::update);
}

void MaskTracker::add(QQuickItem *item)
{
    m_areas.append(item);
    m_window->update(); // request a frame, so the mask is recalculated
}

void MaskTracker::remove(QQuickItem *item)
{
    m_areas.removeOne(item);
    m_window->update();
}

// TODO: Optimization. The mask is recalculated on every frame rendered by the window
// (afterAnimating), even when no MaskArea has moved, e.g. while a ListView scrolls or
// an unrelated animation runs in the same window. Only setMask() is skipped when the
// region did not change. This is cheap for tens of areas, but could be optimized with
// a "dirty" flag set when an area or one of its ancestors changes position, size,
// visibility or transformation (needs tracking of all ancestors, the public Qt Quick API
// has no single "scene position changed" notification). Other limitations: opacity: 0
// and clipping by ancestors (clip: true) are not taken into account, only bounding
// rectangles are used.
void MaskTracker::update()
{
    static uint32_t updateIndex = 0;
    qDebug() << "[ INFO ] MaskTracker::update() : " << updateIndex++;
    QRegion region;
    for (QQuickItem *item : std::as_const(m_areas)) {
        if (item->isVisible()) {
            // mapRectToScene takes ancestor positions and transformations (scale, translate) into account
            region += item->mapRectToScene(QRectF(0, 0, item->width(), item->height())).toAlignedRect();
        }
    }

    // An empty QRegion removes the mask (the whole window receives input),
    // so when nothing is visible we use a region outside of the window
    if (region.isEmpty()) {
        region = QRegion(-1, -1, 1, 1);
    }

    if (region == m_last)
        return;

    m_last = region;
    m_window->setMask(region);
}
