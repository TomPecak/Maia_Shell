#include <QQuickItem>
#include <QQuickWindow>
#include <QRegion>
#include <QList>
#include <QSet>
#include <QTimer>
#include <QElapsedTimer>

#include "./private/WindowInputMask.hpp"

class MMaskedItem : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit MMaskedItem(QQuickItem *parent = nullptr);
    ~MMaskedItem();

protected:
    void itemChange(QQuickItem::ItemChange change, const QQuickItem::ItemChangeData &value) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

public:
    WindowInputMask *m_windowInputMask;
};




