#include "MaskArea.hpp"

MaskArea::MaskArea(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, false);
}

MaskArea::~MaskArea()
{
    if (m_maskTracker)
        m_maskTracker->remove(this);
}

void MaskArea::itemChange(ItemChange change, const ItemChangeData &data)
{
    if (change == ItemSceneChange) {
        if (m_maskTracker)
            m_maskTracker->remove(this);
        m_maskTracker = data.window ? MaskTracker::forWindow(data.window) : nullptr;
        if (m_maskTracker)
            m_maskTracker->add(this);
    }
    QQuickItem::itemChange(change, data);
}
