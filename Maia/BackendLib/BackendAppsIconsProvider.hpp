#pragma once

#include <QQuickImageProvider>
#include <QIcon>
#include <QPixmap>
#include <QString>

class BackendAppsIconsProvider : public QQuickImageProvider
{
public:
    BackendAppsIconsProvider()
        : QQuickImageProvider(QQuickImageProvider::Pixmap)
    {
#warning "Icons should be set in QML"

        QString homePath = qgetenv("HOME");
        QStringList searchPaths;
#warning "Icon path system must be better designed"
        searchPaths << QString(homePath + "/.local/share/icons");
        QIcon::setThemeSearchPaths(searchPaths);
        QIcon::setThemeName("oxygen");
        //QIcon::setThemeName("Windows XP");
    }

    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        QIcon icon = QIcon::fromTheme(id);

        if(icon.isNull()){
            icon = QIcon::fromTheme("xorg");
        }

        if(icon.isNull()){
            return QPixmap();
        }

        QPixmap pixmap = icon.pixmap(requestedSize.isValid() ? requestedSize : QSize(32, 32));
        if (size) {
            *size = pixmap.size();
        }
        return pixmap;
    }
};
