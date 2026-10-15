#include "MMaskedItem.hpp"

MMaskedItem::MMaskedItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, false);
    m_windowInputMask = new WindowInputMask(this, false);
}

MMaskedItem::~MMaskedItem()
{
    delete m_windowInputMask;
}

void MMaskedItem::itemChange(ItemChange change, const ItemChangeData &value)
{
    m_windowInputMask->itemChange(change, value);
    QQuickItem::itemChange(change, value);
}

void MMaskedItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    m_windowInputMask->geometryChange(newGeometry, oldGeometry);
    QQuickItem::geometryChange(newGeometry, oldGeometry);
}
