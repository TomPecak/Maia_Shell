#pragma once

#include <QObject>
#include <QQuickItem>
#include <QQuickWindow>

#include "MaskAlgorithm.hpp"

class MaskTracker : public QObject{
    Q_OBJECT
public:
    explicit MaskTracker(QQuickItem *parent = nullptr, bool useSignals = false);
    ~MaskTracker();

    void itemChange(QQuickItem::ItemChange change, const QQuickItem::ItemChangeData &value);
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry);

private slots:
    void onWindowChanged(QQuickWindow *newWindow);

private:
    static void printTime(QString funcName);
    static void processScheduledMaskUpdates(QQuickWindow * win);
    static void updateMaskForWindow(QQuickWindow *win);
    void scheduleMaskUpdateForWindow(QQuickWindow *win);

    static QSet<QQuickWindow*> pendingUpdates; // Set of windows awaiting updates
    static SimpleMaskAlgorithm maskAlgorithm;
    static QMap<QQuickWindow*, QSet<QQuickItem*>> instances; // List of all MaskedItem instances
    QElapsedTimer elapsedTimer;
    QQuickItem *trackedItem = nullptr;
    QQuickWindow *m_previousWindow = nullptr;
    bool m_useSignals = false;
};
