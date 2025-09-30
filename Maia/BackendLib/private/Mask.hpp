#pragma once

#include <QQuickItem>
#include <QQuickWindow>
#include <QObject>
#include <QMap>
#include <QSet>
#include <QRegion>
#include <QElapsedTimer>

#include "MaskTracker.hpp"

class Mask : public QObject {
    Q_OBJECT
public:
    explicit Mask(QObject *parent = nullptr);
    ~Mask();

    void addMaskedItem(QQuickItem *item);
    void removeMaskedItem(QQuickItem *item);

private:
    QMap<QQuickItem*, MaskTracker*> trackedItems;
};
