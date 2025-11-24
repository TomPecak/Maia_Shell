#include "MBackgroundHelper.h"

#include <QGuiApplication>
#include <QDebug>
#include <QPixmap>
#include <QPixmapCache>
#include <QScreen>
#include <QRgb>
#include <QBuffer>

MBackgroundHelper::MBackgroundHelper(QObject *parent)
    : QObject(parent)
    , m_statusBarHeight(25 / qApp->devicePixelRatio())
    , m_type(0)
    , m_windowX(0)
    , m_windowY(0)
    , m_windowWidth(0)
    , m_windowHeight(0)
{
    onPrimaryScreenChanged();
    connect(qApp, &QGuiApplication::primaryScreenChanged, this, &MBackgroundHelper::onPrimaryScreenChanged);
}

QUrl MBackgroundHelper::wallpaperSource() const { return m_wallpaperSource; }
int MBackgroundHelper::windowX() const { return m_windowX; }
int MBackgroundHelper::windowY() const { return m_windowY; }
int MBackgroundHelper::windowHeight() const { return m_windowHeight; }
int MBackgroundHelper::windowWidth() const { return m_windowWidth; }

void MBackgroundHelper::setWallpaperSource(const QUrl &source)
{
    if (m_wallpaperSource == source) return;

    m_wallpaperSource = source;

    // Update the m_wallpaper string used by internal logic
    if (source.isLocalFile()) {
        m_wallpaper = source.toLocalFile();
    } else {
        m_wallpaper = source.toString();
    }

    emit wallpaperSourceChanged();

    // Set mode to wallpaper and recalculate
    m_type = 0;
    onChanged();
}

void MBackgroundHelper::setWindowX(int x)
{
    if (m_windowX == x) return;
    m_windowX = x;
    emit windowXChanged();
    onChanged();
}

void MBackgroundHelper::setWindowY(int y)
{
    if (m_windowY == y) return;
    m_windowY = y;
    emit windowYChanged();
    onChanged();
}

void MBackgroundHelper::setWindowHeight(int height)
{
    if (m_windowHeight == height) return;
    m_windowHeight = height;
    emit windowHeightChanged();
    onChanged();
}

void MBackgroundHelper::setWindowWidth(int width)
{
    if (m_windowWidth == width) return;
    m_windowWidth = width;
    emit windowWidthChanged();
    onChanged();
}

void MBackgroundHelper::setColor(QColor c)
{
    m_color = c;
    m_type = 1;

    bool isDark = (c.red() * 0.299 +
                   c.green() * 0.587 +
                   c.blue() * 0.114) < 186;

    emit newColor(c, isDark);
    emit debugImageGenerated("");
}

void MBackgroundHelper::setBackgound(const QString &fileName)
{
    m_wallpaper = fileName;
    m_type = 0;

    // Sync QUrl if setBackgound is called directly, ensuring the getter returns the current value
    QUrl newUrl = QUrl::fromUserInput(fileName);
    if (newUrl.isLocalFile() && !fileName.startsWith("file:")) {
        newUrl = QUrl::fromLocalFile(fileName);
    }
    if (m_wallpaperSource != newUrl) {
        m_wallpaperSource = newUrl;
        emit wallpaperSourceChanged();
    }

    if (m_windowWidth <= 0 || m_windowHeight <= 0) {
        // return;
    }

    qDebug() << "Processing background: " << fileName;

    QString localPath = fileName;
    const QUrl url(fileName);
    if (url.isLocalFile()) {
        localPath = url.toLocalFile();
    }

    QImage img(localPath);

    if (img.isNull()) {
        qDebug() << "Image is NULL";
        return;
    }

    QSize screenSize = qApp->primaryScreen()->geometry().size();
    img = img.scaled(screenSize.width(), screenSize.height(), Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);

    // Crop the fragment corresponding to the window position
    QRect windowRect(m_windowX, m_windowY, m_windowWidth, m_windowHeight);

    QRect cropRect = windowRect.intersected(img.rect());

    if (!cropRect.isEmpty()) {
        img = img.copy(cropRect);
    } else {
        img = img.copy(0, 0, 1, 1);
    }

    QSize size(img.size());
    img = img.scaledToWidth(qMax(1, int(size.width() * 0.5)), Qt::SmoothTransformation);
    size = img.size();

    // Image debugging
    QByteArray byteArray;
    QBuffer buffer(&byteArray);
    buffer.open(QIODevice::WriteOnly);
    img.save(&buffer, "PNG");
    QString base64 = QString::fromLatin1(byteArray.toBase64().data());
    emit debugImageGenerated("data:image/png;base64," + base64);

    long long sumR = 0, sumG = 0, sumB = 0;
    int measureArea = size.width() * size.height();

    for (int y = 0; y < size.height(); ++y) {
        QRgb *line = (QRgb *)img.scanLine(y);
        for (int x = 0; x < size.width(); ++x) {
            sumR += qRed(line[x]);
            sumG += qGreen(line[x]);
            sumB += qBlue(line[x]);
        }
    }

    if (measureArea > 0) {
        sumR /= measureArea;
        sumG /= measureArea;
        sumB /= measureArea;
    }

    QColor c = QColor(sumR, sumG, sumB);
    QColor textColor = (sumR * 0.299 +
                        sumG * 0.587 +
                        sumB * 0.114) > 186 ? "#000000" : "#FFFFFF";

    qDebug() << "Calculated color:" << c << " Text:" << textColor;

    emit newColor(c, textColor == "#FFFFFF");

    QPixmapCache::clear();
}

void MBackgroundHelper::onPrimaryScreenChanged()
{
    if (qApp->primaryScreen()) {
        disconnect(qApp->primaryScreen(), nullptr, this, nullptr);
        connect(qApp->primaryScreen(), &QScreen::geometryChanged, this, &MBackgroundHelper::onChanged);
        connect(qApp->primaryScreen(), &QScreen::virtualGeometryChanged, this, &MBackgroundHelper::onChanged);
    }
}

void MBackgroundHelper::onChanged()
{
    switch (m_type) {
    case 0:
        setBackgound(m_wallpaper);
        break;
    case 1:
        setColor(m_color);
        break;
    default:
        break;
    }
}
