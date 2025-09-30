#pragma once

#include <QRegion>
#include <QQuickWindow>
#include <QQuickItem>
#include <QMap>
#include <QList>
#include <QTimer>

class MaskAlgorithm : public QObject {
    Q_OBJECT

public:
    explicit MaskAlgorithm(QObject *parent = nullptr);
    virtual ~MaskAlgorithm() = default;
};


class SimpleMaskAlgorithm : public MaskAlgorithm {
    Q_OBJECT

public:
    explicit SimpleMaskAlgorithm(QObject * parent = nullptr, int maxRegionsPerItem = /*6*/ 3, int maxAgeMs = 80);
    void updateMask(QQuickWindow *win, QMap<QQuickWindow*, QSet<QQuickItem*>> *instances);

private:
    void postUpdate(QQuickWindow *win, QMap<QQuickWindow*, QSet<QQuickItem*>> *instances);
    QRegion calculateMaskForWindow(QQuickWindow *win, QMap<QQuickWindow*, QSet<QQuickItem*>> *instances);
    QRegion calculateItemMask(QQuickItem *item);
    void updateMaskHistory(QQuickWindow *win, const QRegion currentMask, qint64 timestamp);
    void schedulePostUpdate(QQuickWindow *win, QMap<QQuickWindow*, QSet<QQuickItem*>> *instances);

    QMap<QQuickWindow*, QList<QPair<QRegion, qint64>>> maskStorage;
    QMap<QQuickItem *, bool> previousVisible;
    QMap<QQuickWindow*, QTimer*> postUpdateTimers;
    QElapsedTimer timer;
    qint64 maxAgeMs;
    int maxRegionsPerItem;
    const int padding = 0;
};


