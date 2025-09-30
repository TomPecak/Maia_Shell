#include "MaskAlgorithm.hpp"

MaskAlgorithm::MaskAlgorithm(QObject *parent) : QObject(parent) {}

SimpleMaskAlgorithm::SimpleMaskAlgorithm(QObject *parent, int maxRegionsPerItem, int maxAgeMs)
    : MaskAlgorithm(parent),
    maxRegionsPerItem(maxRegionsPerItem),
    maxAgeMs(maxAgeMs) {
    timer.start(); //We start measuring time
}

void SimpleMaskAlgorithm::updateMask(QQuickWindow *win, QMap<QQuickWindow *, QSet<QQuickItem *> > *instances) {
    if (!win) return;

    qint64 currentTime = timer.elapsed();
    QRegion currentMask = calculateMaskForWindow(win, instances);
    QRegion maskWithHistory = currentMask; // We start with the current mask

    // We add masks from the history to the result
    if (maskStorage.contains(win)) {
        for (const QPair<QRegion, qint64> &entry : maskStorage[win]) {
            if((currentTime - entry.second) < maxAgeMs)
                maskWithHistory += entry.first;
        }
    }

    // Updating the history
    updateMaskHistory(win, currentMask, currentTime);
    win->setMask(maskWithHistory);
    schedulePostUpdate(win, instances);
}

void SimpleMaskAlgorithm::postUpdate(QQuickWindow *win, QMap<QQuickWindow *, QSet<QQuickItem *> > *instances) {
    if (!win) return;

    QRegion mask = calculateMaskForWindow(win, instances);
    maskStorage[win].clear();
    win->setMask(mask);
}

QRegion SimpleMaskAlgorithm::calculateMaskForWindow(QQuickWindow *win, QMap<QQuickWindow *, QSet<QQuickItem *> > *instances) {
    QRegion mask;
    if (!win || !instances || !instances->contains(win)) {
        return mask;
    }

    const QSet<QQuickItem*> items = instances->value(win);
    for (QQuickItem *item : items) {
        mask += calculateItemMask(item);
    }

    return mask;
}

QRegion SimpleMaskAlgorithm::calculateItemMask(QQuickItem *item) {
    bool prevVisible = previousVisible[item];
    previousVisible[item] = item->isVisible();
    if (!item || item->width() <= 0 || item->height() <= 0 || (!item->isVisible() && !prevVisible)) {
        return QRegion();
    }

    QRect sceneRect = item->mapRectToScene(item->boundingRect()).toAlignedRect();
    return QRegion(sceneRect.adjusted(-padding, -padding, padding, padding));
}

void SimpleMaskAlgorithm::updateMaskHistory(QQuickWindow *win, const QRegion currentMask, qint64 timestamp) {
    QList<QPair<QRegion, qint64>> &history = maskStorage[win];

    history.append(qMakePair(currentMask, timestamp));

    auto it = history.begin();
    while (it != history.end() && (timestamp - it->second > maxAgeMs || history.size() > maxRegionsPerItem)) {
        it = history.erase(it);
    }
}

void SimpleMaskAlgorithm::schedulePostUpdate(QQuickWindow *win, QMap<QQuickWindow *, QSet<QQuickItem *> > *instances) {
    if (!postUpdateTimers.contains(win)) {
        QTimer *timer = new QTimer(this);
        timer->setSingleShot(true);
        postUpdateTimers[win] = timer;

        connect(timer, &QTimer::timeout, this, [this, win, instances, timer]() {
            postUpdate(win, instances);
            postUpdateTimers.remove(win);
            timer->deleteLater();
        });
    }
    postUpdateTimers[win]->start(3*16);
}
