#include "Mask.hpp"
#include <QDebug>
#include <QTimer>

Mask::Mask(QObject *parent) : QObject(parent) {}

Mask::~Mask() {
    for (WindowInputMask* tracker : trackedItems.values()) {
        delete tracker;
    }
    trackedItems.clear();
}

void Mask::addMaskedItem(QQuickItem *item) {
    //qDebug() << __PRETTY_FUNCTION__;
    if (!item || trackedItems.contains(item)) return;
    WindowInputMask* maskTracker = new WindowInputMask(item, true);
    trackedItems[item] = maskTracker;
}

void Mask::removeMaskedItem(QQuickItem *item) {
    //qDebug() << __PRETTY_FUNCTION__;
    if (!item || !trackedItems.contains(item)) return;
    WindowInputMask* tracker = trackedItems.take(item);
    delete tracker;
}

