#include "MMaskedItem.hpp"

MMaskedItem::MMaskedItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, false);
    m_maskTracker = new MaskTracker(this, false);
}

MMaskedItem::~MMaskedItem()
{
    delete m_maskTracker;
}

void MMaskedItem::itemChange(ItemChange change, const ItemChangeData &value)
{
    m_maskTracker->itemChange(change, value);
    QQuickItem::itemChange(change, value);
}

void MMaskedItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    m_maskTracker->geometryChange(newGeometry, oldGeometry);
    QQuickItem::geometryChange(newGeometry, oldGeometry);
}
