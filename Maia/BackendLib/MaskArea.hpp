#pragma once

#include <QPointer>
#include <QQuickItem>

#include "./private/MaskTracker.hpp"

// Used in QML like a MouseArea: the area it fills receives mouse events,
// the rest of the window lets input through to the windows below.
class MaskArea : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit MaskArea(QQuickItem *parent = nullptr);
    ~MaskArea() override;

protected:
    void itemChange(ItemChange change, const ItemChangeData &data) override;

private:
    QPointer<MaskTracker> m_maskTracker;
};
