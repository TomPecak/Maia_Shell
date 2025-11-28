#pragma once

#include <qqml.h>
#include <QQuickWindow>
#include <QTimer>

class MControlCenterDialog : public QQuickWindow
{
    Q_OBJECT
    QML_ELEMENT

public:
    MControlCenterDialog(QQuickWindow *view = nullptr);

    Q_INVOKABLE void open();

protected:
    bool eventFilter(QObject *object, QEvent *event);
};
