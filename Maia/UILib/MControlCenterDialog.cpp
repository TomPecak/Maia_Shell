#include "MControlCenterDialog.hpp"
#include <KX11Extras>

MControlCenterDialog::MControlCenterDialog(QQuickWindow *parent)
    : QQuickWindow(parent)
{
    setFlags(Qt::Popup);
    setColor(Qt::transparent);
    installEventFilter(this);
}

void MControlCenterDialog::open()
{
    setVisible(true);
    setMouseGrabEnabled(true);
    setKeyboardGrabEnabled(true);
}

bool MControlCenterDialog::eventFilter(QObject *object, QEvent *event)
{
    if (event->type() == QEvent::MouseButtonPress) {
        if (QWindow *w = qobject_cast<QWindow*>(object)) {
            if (!w->geometry().contains(static_cast<QMouseEvent*>(event)->globalPos())) {
                MControlCenterDialog::setVisible(false);
            }
        }
    } else if (event->type() == QEvent::KeyPress) {
        QKeyEvent *keyEvent = static_cast<QKeyEvent*>(event);
        if (keyEvent->key() == Qt::Key_Escape) {
            MControlCenterDialog::setVisible(false);
        }
    } else if (event->type() == QEvent::Show) {
        KX11Extras::setState(winId(), NET::SkipTaskbar | NET::SkipPager | NET::SkipSwitcher);
    } else if (event->type() == QEvent::Hide) {
        setMouseGrabEnabled(false);
        setKeyboardGrabEnabled(false);
    }

    return QObject::eventFilter(object, event);
}
