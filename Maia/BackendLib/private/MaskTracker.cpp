#include "MaskTracker.hpp"

#include <QQuickWindow>

#include "../MMaskedItem.hpp"

QMap<QQuickWindow*, QSet<QQuickItem*>> MaskTracker::instances;
QSet<QQuickWindow*> MaskTracker::pendingUpdates;
SimpleMaskAlgorithm MaskTracker::maskAlgorithm;

MaskTracker::MaskTracker(QQuickItem *parent, bool useSignals):
    QObject(parent),
    m_useSignals(useSignals){
    //qDebug() << __PRETTY_FUNCTION__;
    trackedItem = parent;

    if (!trackedItem) return;

    // Add this item to the list of instances
    QQuickWindow *win = trackedItem->window();
    if(win)
        instances[win].insert(trackedItem);

    if(m_useSignals){
        connect(trackedItem, &QQuickItem::visibleChanged, this, [this]() {
            scheduleMaskUpdateForWindow(trackedItem->window());
        });
        connect(trackedItem, &QQuickItem::parentChanged, this, [this]() {
            scheduleMaskUpdateForWindow(trackedItem->window());
        });
        connect(trackedItem, &QQuickItem::widthChanged, this, [this]() {
            scheduleMaskUpdateForWindow(trackedItem->window());
        });
        connect(trackedItem, &QQuickItem::heightChanged, this, [this]() {
            scheduleMaskUpdateForWindow(trackedItem->window());
        });
        connect(trackedItem, &QQuickItem::xChanged, this, [this]() {
            scheduleMaskUpdateForWindow(trackedItem->window());
        });
        connect(trackedItem, &QQuickItem::yChanged, this, [this]() {
            scheduleMaskUpdateForWindow(trackedItem->window());
        });
    }

    connect(trackedItem, &QQuickItem::windowChanged, this, &MaskTracker::onWindowChanged);

    scheduleMaskUpdateForWindow(trackedItem->window());
}

MaskTracker::~MaskTracker()
{
    //qDebug() << __PRETTY_FUNCTION__;
    instances[trackedItem->window()].remove(trackedItem);
    scheduleMaskUpdateForWindow(trackedItem->window()); // Schedule an update for the window upon removal
}

void MaskTracker::onWindowChanged(QQuickWindow *newWindow)
{
    //qDebug() << __PRETTY_FUNCTION__;
    if (m_previousWindow) {
        instances[m_previousWindow].remove(trackedItem);
        scheduleMaskUpdateForWindow(m_previousWindow); // Report an update for the old window
    }

    m_previousWindow = newWindow;
    if(newWindow){
        instances[newWindow].insert(trackedItem);
        scheduleMaskUpdateForWindow(newWindow); // Report an update for the new window
    }
}

void MaskTracker::scheduleMaskUpdateForWindow(QQuickWindow *win)
{
    if (!win || pendingUpdates.contains(win)) return;

    pendingUpdates.insert(win);

    //MaskedItem::processScheduledMaskUpdates(win); //working implementation

    QTimer::singleShot(0, win, [win]() {
        MaskTracker::processScheduledMaskUpdates(win);
    });

}

void MaskTracker::itemChange(QQuickItem::ItemChange change, const QQuickItem::ItemChangeData &value)
{
    if(m_useSignals)
        return;

    switch (change) {
    case QQuickItem::ItemSceneChange:
    case QQuickItem::ItemVisibleHasChanged:
    case QQuickItem::ItemParentHasChanged:
        scheduleMaskUpdateForWindow(trackedItem->window());
        break;
    default:
        break;
    }
}

void MaskTracker::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    if(m_useSignals)
        return;

    scheduleMaskUpdateForWindow(trackedItem->window());
}

void MaskTracker::printTime(QString funcName)
{
    //qDebug() << __PRETTY_FUNCTION__;
    static QMap<QString, qint64> prevTimes;
    static qint64 prevTime;
    qint64 currTime = QDateTime::currentMSecsSinceEpoch();
    qDebug() << "t=" << QDateTime::currentMSecsSinceEpoch() << "mill dt=" << currTime - prevTimes[funcName] << "ms "  << " ddt=" << QDateTime::currentMSecsSinceEpoch() - prevTime << "ms "<<   funcName << "()";
    prevTimes[funcName] = currTime;
    prevTime = currTime;
}

void MaskTracker::processScheduledMaskUpdates(QQuickWindow * win)
{
    //qDebug() << __PRETTY_FUNCTION__;
    if (!win || !pendingUpdates.contains(win)) return;

    updateMaskForWindow(win);

    pendingUpdates.remove(win);
}

void MaskTracker::updateMaskForWindow(QQuickWindow *win)
{
    //qDebug() << __PRETTY_FUNCTION__;
    if (!win) return;
    maskAlgorithm.updateMask(win, &instances);
}

