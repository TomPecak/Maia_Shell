#pragma once
#include <QMap>
#include <QQuickWindow>
#include <QObject>
#include <QSet>

#include "Strut.hpp"

class StrutManager: public QObject {
    Q_OBJECT
public:
    explicit StrutManager(QObject *parent = nullptr);
    void reservePanelTopArea(QQuickWindow *window, int x, int y, int width, int height);
    void reservePanelLeftArea(QQuickWindow *window, int x, int y, int width, int height);
    void reservePanelRightArea(QQuickWindow *window, int x, int y, int width, int height);
    void reservePanelBottomArea(QQuickWindow *window, int x, int y, int width, int height);

signals:
    void updateRequested(QQuickWindow *window);

private slots:
    void updateStructForWindow(QQuickWindow *window);

private:
    QMap<QQuickWindow *, Strut> struts;
    QSet<QQuickWindow *> pendingUpdates;
};


