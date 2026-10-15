#pragma once

#include <QList>
#include <QObject>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegion>

// TODO
// One per window, created automatically by the first MaskArea in that window.
// Once per rendered frame it merges the rectangles of all visible MaskArea items
// into the window input mask (on Wayland: the wl_surface input region).
class MaskTracker : public QObject
{
    Q_OBJECT
public:
    static MaskTracker *forWindow(QQuickWindow *window);

    void add(QQuickItem *item);
    void remove(QQuickItem *item);

private:
    explicit MaskTracker(QQuickWindow *window);

    void update();

    QQuickWindow *m_window;
    QList<QQuickItem *> m_areas;
    QRegion m_last;
};
