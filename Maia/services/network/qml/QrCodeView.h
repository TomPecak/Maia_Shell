#pragma once

// Draws a QR code from its modules (NetworkControl.qrCode), sharp at any size:
//
//   QrCodeView { width: 220; height: 220; moduleCount: code.size; modules: code.modules }
//
// Whole pixels per module when the item is large enough (no blurred edges), centered, with a
// light quiet zone around it (4 modules, as the standard asks: phones find the code faster).

#include <QByteArray>
#include <QColor>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

class QrCodeView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT

    // size x size, row by row, 1 = dark
    Q_PROPERTY(QByteArray modules READ modules WRITE setModules NOTIFY changed)
    Q_PROPERTY(int moduleCount READ moduleCount WRITE setModuleCount NOTIFY changed)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY changed)
    Q_PROPERTY(QColor background READ background WRITE setBackground NOTIFY changed)
    // In modules
    Q_PROPERTY(int quietZone READ quietZone WRITE setQuietZone NOTIFY changed)

public:
    explicit QrCodeView(QQuickItem *parent = nullptr);

    QByteArray modules() const { return m_modules; }
    void setModules(const QByteArray &modules);
    int moduleCount() const { return m_count; }
    void setModuleCount(int count);
    QColor color() const { return m_color; }
    void setColor(const QColor &color);
    QColor background() const { return m_background; }
    void setBackground(const QColor &color);
    int quietZone() const { return m_quietZone; }
    void setQuietZone(int modules);

    void paint(QPainter *painter) override;

Q_SIGNALS:
    void changed();

private:
    void changedSomething();

    QByteArray m_modules;
    int m_count = 0;
    QColor m_color = Qt::black;
    QColor m_background = Qt::white;
    int m_quietZone = 4;
};

} // namespace MaiaNetwork
