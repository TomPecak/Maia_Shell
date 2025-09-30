#include "TaskbarIconProvider.hpp"

#include <X11/Xatom.h>
#include <X11/Xdefs.h>

#include <QFile>
#include <QTimer>

#include <KX11Extras>
#include <kwindowinfo.h>

QDebug operator<<(QDebug dbg, const KWindowInfo &info) {
    if (!info.valid()) {
        dbg.nospace() << "KWindowInfo(Invalid data)";
        return dbg.space();
    }

    auto windowTypeToString = [](NET::WindowType type) -> QString {
        switch (type) {
        case NET::Unknown: return "Unknown";
        case NET::Normal: return "Normal";
        case NET::Desktop: return "Desktop";
        case NET::Dock: return "Dock";
        case NET::Toolbar: return "Toolbar";
        case NET::Menu: return "Menu";
        case NET::Dialog: return "Dialog";
        case NET::Override: return "Override";
        case NET::TopMenu: return "TopMenu";
        case NET::Utility: return "Utility";
        case NET::Splash: return "Splash";
        case NET::DropdownMenu: return "DropdownMenu";
        case NET::PopupMenu: return "PopupMenu";
        case NET::Tooltip: return "Tooltip";
        case NET::Notification: return "Notification";
        case NET::ComboBox: return "ComboBox";
        case NET::DNDIcon: return "DNDIcon";
        case NET::OnScreenDisplay: return "OnScreenDisplay";
        case NET::CriticalNotification: return "CriticalNotification";
        case NET::AppletPopup: return "AppletPopup";
        default: return "Other";
        }
    };

    dbg.nospace() << "KWindowInfo:\n"
                  << "\tWindow ID: " << info.win() << "\n"
                  << "\tValid: " << info.valid() << "\n"
                  << "\tName: " << info.name() << "\n"
                  << "\tVisible Name: " << info.visibleName() << "\n"
                  << "\tIcon Name: " << info.iconName() << "\n"
                  << "\tDesktop: " << info.desktop() << "\n"
                  << "\tState: " << info.state() << "\n"
                  << "\tMinimized: " << info.isMinimized() << "\n"
                  << "\tOn Current Desktop: " << info.isOnCurrentDesktop() << "\n"
                  << "\tFrame Geometry: " << info.frameGeometry() << "\n"
                  << "\tGeometry: " << info.geometry() << "\n"
                  << "\tClient Machine: " << info.clientMachine() << "\n"
                  << "\tWindow Class Name: " << info.windowClassName() << "\n"
                  << "\tWindow Class Class: " << info.windowClassClass() << "\n"
                  << "\tGTK Application ID: " << info.gtkApplicationId() << "\n"
                  << "\tTransient For: " << info.transientFor() << "\n"
                  << "\tActivities: " << info.activities().join(", ") << "\n"
                  << "\tWindow Type: "
                  << windowTypeToString(info.windowType(NET::AllTypesMask)) << "\n"; // Dodano typ okna

    return dbg.space();
}



TaskbarIconsProvider::TaskbarIconsProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
{
}

TaskbarIconsProvider::~TaskbarIconsProvider(){

}

QPixmap TaskbarIconsProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    //CONVER QString id to WId
    bool ok;
    WId win = static_cast<WId>(id.toULongLong(&ok)); // lub toUInt() dla 32-bitowej platformy
    if (!ok) {
        return QPixmap();
    }

    //CHECK REQUESTET SIZE
    QSize actualSize = requestedSize.isValid() ? requestedSize : QSize(16, 16);

    //GET PIXMAP
    QPixmap pixmap = KX11Extras::icon(win, actualSize.width(), actualSize.height());
    if (size) {
        *size = pixmap.size();
    }
    return pixmap;
}

QString TaskbarIconsProvider::getProcessNameByPid(qint64 pid) {
    QString filePath = QString("/proc/%1/comm").arg(pid);
    QFile file(filePath);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&file);
        QString processName = in.readLine().trimmed();
        file.close();
        return processName;
    } else {
        qDebug() << "Failed to open file:" << filePath;
        return QString();
    }
}



