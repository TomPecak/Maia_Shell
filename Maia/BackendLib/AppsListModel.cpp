#include "AppsListModel.hpp"
#include <algorithm>

#include <KDesktopFile>
#include <KConfigGroup>

Application parseDesktopFile(const QString& filePath);
bool compareApplications(const Application &a, const Application &b);
QDebug operator<<(QDebug debug, const Application &app);
QList<Application> getApplications();

QDebug operator<<(QDebug debug, const Application &app) {
    QDebugStateSaver saver(debug);
    debug.nospace() << "Application(Name: " << app.name
                    << ", Exec: " << app.exec
                    << ", Icon: " << app.icon << ")";
    return debug;
}

Application parseDesktopFile(const QString& filePath) {
    KDesktopFile desktopFile(filePath);

    if (!desktopFile.hasApplicationType()) {
        return {};
    }

    Application app;
    KConfigGroup desktopGroup = desktopFile.desktopGroup();

    if(!desktopFile.noDisplay()){
        app.name = desktopGroup.readEntry("Name", QString());
        app.exec = desktopGroup.readEntry("Exec", QString());
        app.id = app.exec; //We are using exec as the ID, but is this a good solution?
        //app.icon = desktopGroup.readEntry("Icon", QString());
        app.icon = desktopFile.readIcon();
    }

    return app;
}

bool compareApplications(const Application &a, const Application &b) {
    return a.name.toLower() < b.name.toLower();
}

QList<Application> getApplications() {
    QList<Application> apps;

#warning "Zmierzyć czas ładowania aplikacji, bo zmianie wczytywania menu za pomoca bibliotek KDE znaczaco wydłużł sie czas ładowania aplikacji"

    QString xdgDataDirs = qgetenv("XDG_DATA_DIRS");
    if (xdgDataDirs.isEmpty()) {
        xdgDataDirs = "/usr/local/share:/usr/share";
    }

    QStringList desktopDirs = xdgDataDirs.split(":", Qt::SkipEmptyParts);
    desktopDirs.append(QDir::homePath() + "/.local/share/applications/");

    for (const QString& dir : desktopDirs) {
        QDir applicationDir(dir + "/applications");
        if (!applicationDir.exists()) {
            continue;
        }

        QStringList desktopFiles = applicationDir.entryList({"*.desktop"}, QDir::Files);
        for (const QString& fileName : desktopFiles) {
            QString filePath = applicationDir.filePath(fileName);
            Application app = parseDesktopFile(filePath);
            if (!app.name.isEmpty() && !apps.contains(app)) {
                apps.append(app);
            }
        }
    }

    std::sort(apps.begin(), apps.end(), compareApplications);
    return apps;
}

ApplicationModel::ApplicationModel(QObject *parent) : QAbstractListModel(parent) {
    apps = getApplications();
}

int ApplicationModel::rowCount(const QModelIndex &parent) const {
    Q_UNUSED(parent);
    return apps.size();
}

QVariant ApplicationModel::data(const QModelIndex &index, int role) const {
    if (index.row() < 0 || index.row() >= apps.size()){
        return QVariant();
    }

    const Application &app = apps[index.row()];
    if (role == NameRole){
        return app.name;
    }
    else if (role == ExecRole){
        return app.exec;
    }
    else if (role == IconRole){
        return app.icon;
    }
    else if (role == IdRole){
        return app.id;
    }
    return QVariant();
}

QHash<int, QByteArray> ApplicationModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[NameRole] = "name";
    roles[ExecRole] = "exec";
    roles[IconRole] = "icon";
    roles[IdRole] = "id";
    return roles;
}

QString ApplicationModel::getExecById(const QString &appId) const {
    for (const Application& app : apps) {
        if (app.id == appId) {
            return app.exec;
        }
    }
    return QString("");
}

Application ApplicationModel::getApplicationById(const QString &appId) const
{
    for (const Application &app : apps) {
        if (app.id == appId) {
            return app;
        }
    }
    return {};
}
