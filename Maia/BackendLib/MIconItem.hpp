#pragma once

#include <QQuickPaintedItem>
#include <QPixmap>
#include <QPixmapCache>
#include <QIcon>

class MIconItem : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariant source READ source WRITE setSource NOTIFY sourceChanged)

public:
    MIconItem(QQuickItem *parent = nullptr);
    ~MIconItem();

    void setSource(const QVariant &source);
    QVariant source() const;

    void paint(QPainter *painter) override;

    Q_INVOKABLE void updateIcon();

signals:
    void sourceChanged();

protected:
    void loadPixmap();
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    QVariant m_source;

    QIcon m_icon;
    QImage m_image;

    QString m_iconName;
    QPixmap m_iconPixmap;
};
