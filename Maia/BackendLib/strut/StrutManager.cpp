#include "StrutManager.hpp"
#include <QDebug>
#include <KX11Extras>

StrutManager::StrutManager(QObject *parent) : QObject(parent) {}

void StrutManager::reservePanelTopArea(QQuickWindow *window, int x, int y, int width, int height) {
    Strut &strut = struts[window];  // Get or create strut for this window
    strut.topStrut = QRegion(x, y, width, height);

    if (!pendingUpdates.contains(window)) {
        pendingUpdates.insert(window);

        //We call this method in the next iteration of the event loop because, if we run it directly from
        //QML while the QML file is still loading, the window ID has not yet been initialized. We need to
        //wait until the window is created before we can set the area occupied by the panel.

        QMetaObject::invokeMethod(this, [=]() {
            if (window) {
                updateStructForWindow(window);
                pendingUpdates.remove(window); // Remove after execution
            } else {
                qDebug() << "window id is empty";
            }
        }, Qt::QueuedConnection);
    }
}

void StrutManager::reservePanelLeftArea(QQuickWindow *window, int x, int y, int width, int height) {
    Strut &strut = struts[window];
    strut.leftStrut = QRegion(x, y, width, height);

    if (!pendingUpdates.contains(window)) {
        pendingUpdates.insert(window);

        //We call this method in the next iteration of the event loop because, if we run it directly from
        //QML while the QML file is still loading, the window ID has not yet been initialized. We need to
        //wait until the window is created before we can set the area occupied by the panel.

        QMetaObject::invokeMethod(this, [=]() {
            if (window) {
                updateStructForWindow(window);
                pendingUpdates.remove(window);
            } else {
                qDebug() << "window id is empty";
            }
        }, Qt::QueuedConnection);
    }
}

void StrutManager::reservePanelRightArea(QQuickWindow *window, int x, int y, int width, int height) {
    Strut &strut = struts[window];
    strut.rightStrut = QRegion(x, y, width, height);

    if (!pendingUpdates.contains(window)) {
        pendingUpdates.insert(window);

        //We call this method in the next iteration of the event loop because, if we run it directly from
        //QML while the QML file is still loading, the window ID has not yet been initialized. We need to
        //wait until the window is created before we can set the area occupied by the panel.

        QMetaObject::invokeMethod(this, [=]() {
            if (window) {
                updateStructForWindow(window);
                pendingUpdates.remove(window);
            } else {
                qDebug() << "window id is empty";
            }
        }, Qt::QueuedConnection);
    }
}

void StrutManager::reservePanelBottomArea(QQuickWindow *window, int x, int y, int width, int height) {
    Strut &strut = struts[window];
    strut.bottomStrut = QRegion(x, y, width, height);

    if (!pendingUpdates.contains(window)) {
        pendingUpdates.insert(window);

        //We call this method in the next iteration of the event loop because, if we run it directly from
        //QML while the QML file is still loading, the window ID has not yet been initialized. We need to
        //wait until the window is created before we can set the area occupied by the panel.

        QMetaObject::invokeMethod(this, [=]() {
            if (window) {
                updateStructForWindow(window);
                pendingUpdates.remove(window);
            } else {
                qDebug() << "window id is empty";
            }
        }, Qt::QueuedConnection);
    }
}

void StrutManager::updateStructForWindow(QQuickWindow *window) {
    if (!struts.contains(window)) {
        return;
    }

    const Strut &strut = struts[window];
    WId windowId = window->winId();

    // Calculate parameters for KX11Extras::setExtendedStrut
    int leftWidth = strut.leftStrut.isEmpty() ? 0 : strut.leftStrut.boundingRect().width();
    int leftY = strut.leftStrut.isEmpty() ? 0 : strut.leftStrut.boundingRect().y();
    int leftEndY = strut.leftStrut.isEmpty() ? 0 : (leftY + strut.leftStrut.boundingRect().height());

    int rightWidth = strut.rightStrut.isEmpty() ? 0 : strut.rightStrut.boundingRect().width();
    int rightY = strut.rightStrut.isEmpty() ? 0 : strut.rightStrut.boundingRect().y();
    int rightEndY = strut.rightStrut.isEmpty() ? 0 : (rightY + strut.rightStrut.boundingRect().height());

    int topHeight = strut.topStrut.isEmpty() ? 0 : strut.topStrut.boundingRect().height();
    int topX = strut.topStrut.isEmpty() ? 0 : strut.topStrut.boundingRect().x();
    int topEndX = strut.topStrut.isEmpty() ? 0 : (topX + strut.topStrut.boundingRect().width());

    int bottomHeight = strut.bottomStrut.isEmpty() ? 0 : strut.bottomStrut.boundingRect().height();
    int bottomX = strut.bottomStrut.isEmpty() ? 0 : strut.bottomStrut.boundingRect().x();
    int bottomEndX = strut.bottomStrut.isEmpty() ? 0 : (bottomX + strut.bottomStrut.boundingRect().width());

    //qDebug() << "bottomHeight = " << bottomHeight << "bottomX = " << bottomX << "bottomEndX = " << bottomEndX;

    KX11Extras::setExtendedStrut(
        windowId,
        leftWidth, leftY, leftEndY,
        rightWidth, rightY, rightEndY,
        topHeight, topX, topEndX,
        bottomHeight, bottomX, bottomEndX
        );
}
