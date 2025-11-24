#pragma once

#include <qqml.h>
#include <QObject>
#include <QColor>
#include <QUrl>

class MBackgroundHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QUrl wallpaperSource READ wallpaperSource WRITE setWallpaperSource NOTIFY wallpaperSourceChanged)
    Q_PROPERTY(int windowX READ windowX WRITE setWindowX NOTIFY windowXChanged)
    Q_PROPERTY(int windowY READ windowY WRITE setWindowY NOTIFY windowYChanged)
    Q_PROPERTY(int windowHeight READ windowHeight WRITE setWindowHeight NOTIFY windowHeightChanged)
    Q_PROPERTY(int windowWidth READ windowWidth WRITE setWindowWidth NOTIFY windowWidthChanged)

public:
    explicit MBackgroundHelper(QObject *parent = nullptr);

    QUrl wallpaperSource() const;
    int windowX() const;
    int windowY() const;
    int windowHeight() const;
    int windowWidth() const;

    void setWallpaperSource(const QUrl &source);
    void setWindowX(int x);
    void setWindowY(int y);
    void setWindowHeight(int height);
    void setWindowWidth(int width);

    Q_INVOKABLE void setColor(QColor c);
    Q_INVOKABLE void setBackgound(const QString &fileName);

private slots:
    void onPrimaryScreenChanged();
    void onChanged();

signals:
    void newColor(QColor color, bool darkMode);
    void debugImageGenerated(QString imageSource);
    void wallpaperSourceChanged();
    void windowXChanged();
    void windowYChanged();
    void windowHeightChanged();
    void windowWidthChanged();

private:
    int m_statusBarHeight;
    int m_type;
    QColor m_color;
    QString m_wallpaper;
    QUrl m_wallpaperSource;

    int m_windowX;
    int m_windowY;
    int m_windowWidth;
    int m_windowHeight;
};
