#ifndef MMENUPOPUPWINDOW_H
#define MMENUPOPUPWINDOW_H

#include <QQuickWindow>
#include <QQuickItem>
#include <QPointer>

class MMenuPopupWindow : public QQuickWindow
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickItem *popupContentItem READ popupContentItem WRITE setPopupContentItem)
    Q_CLASSINFO("DefaultProperty", "popupContentItem")
    Q_PROPERTY(QQuickItem *parentItem READ parentItem WRITE setParentItem)

public:
    MMenuPopupWindow(QQuickWindow *parent = nullptr);

    QQuickItem *popupContentItem() const { return m_contentItem; }
    void setPopupContentItem(QQuickItem *popupContentItem);

    QQuickItem *parentItem() const { return m_parentItem; }
    virtual void setParentItem(QQuickItem *);

public slots:
    Q_INVOKABLE void show();
    Q_INVOKABLE void dismissPopup();
    Q_INVOKABLE void updateGeometry();

signals:
    void popupDismissed();
    void geometryChanged();

protected:
    void mousePressEvent(QMouseEvent *) override;
    void mouseReleaseEvent(QMouseEvent *) override;
    void mouseMoveEvent(QMouseEvent *) override;
    bool event(QEvent *) override;

protected slots:
    void applicationStateChanged(Qt::ApplicationState state);

private:
    QQuickItem *m_parentItem;
    QPointer<QQuickItem> m_contentItem;
    bool m_mouseMoved;
    bool m_dismissed;
};

#endif // MMENUPOPUPWINDOW_H
