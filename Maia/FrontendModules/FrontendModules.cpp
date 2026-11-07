#include "FrontendModules.hpp"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QStandardPaths>

namespace {

// Removes the symlinks and the directory itself, never what the links point to
void removeModulesDir(const QString &path)
{
    QDir modulesDir(path);
    for (const QString &link : modulesDir.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System))
        QFile::remove(modulesDir.filePath(link));
    modulesDir.rmdir(path);
}

// Directories left by processes that did not exit cleanly (e.g. the compositor went away)
void removeStaleModulesDirs(const QString &maiaRuntimeDir)
{
    const QDir dir(maiaRuntimeDir);
    for (const QString &name : dir.entryList({QStringLiteral("qml-modules-*")}, QDir::Dirs | QDir::NoDotAndDotDot)) {
        bool ok = false;
        const qint64 pid = name.mid(int(qstrlen("qml-modules-"))).toLongLong(&ok);
        if (ok && !QFileInfo::exists(QStringLiteral("/proc/") + QString::number(pid)))
            removeModulesDir(dir.filePath(name));
    }
}

} // namespace

FrontendModules::~FrontendModules()
{
    if (!m_modulesDir.isEmpty())
        removeModulesDir(m_modulesDir);
}

bool FrontendModules::registerForFile(QQmlEngine &engine, const QString &qmlFilePath)
{
    // The frontend root: the nearest parent directory with shell/Main.qml and a qmldir
    QDir dir = QFileInfo(qmlFilePath).absoluteDir();
    while (!(dir.exists(QStringLiteral("shell/Main.qml")) && dir.exists(QStringLiteral("qmldir")))) {
        if (!dir.cdUp()) {
            qDebug() << "[ INFO ]" << __PRETTY_FUNCTION__ << qmlFilePath << "is not part of a frontend module";
            return false;
        }
    }
    const QString rootPath = dir.canonicalPath();

    QFile qmldir(dir.filePath(QStringLiteral("qmldir")));
    if (!qmldir.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qDebug() << "[ERROR]" << __PRETTY_FUNCTION__ << "cannot read" << qmldir.fileName();
        return false;
    }
    static const QRegularExpression moduleLine(QStringLiteral("^\\s*module\\s+(\\w+)\\s*$"),
                                               QRegularExpression::MultilineOption);
    const QString uri = moduleLine.match(QString::fromUtf8(qmldir.readAll())).captured(1);
    if (uri.isEmpty()) {
        qDebug() << "[ERROR]" << __PRETTY_FUNCTION__ << "no \"module <URI>\" line in" << qmldir.fileName();
        return false;
    }

    if (m_modulesDir.isEmpty()) {
        QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
        if (runtimeDir.isEmpty())
            runtimeDir = QDir::tempPath();
        removeStaleModulesDirs(runtimeDir + QStringLiteral("/maia"));
        const QString modulesDir = runtimeDir + QStringLiteral("/maia/qml-modules-")
                                   + QString::number(QCoreApplication::applicationPid());
        if (!QDir().mkpath(modulesDir)) {
            qDebug() << "[ERROR]" << __PRETTY_FUNCTION__ << "cannot create" << modulesDir;
            return false;
        }
        m_modulesDir = modulesDir;
    }
    if (!engine.importPathList().contains(m_modulesDir))
        engine.addImportPath(m_modulesDir);

    const QString linkPath = m_modulesDir + QLatin1Char('/') + uri;
    QFile::remove(linkPath);
    if (!QFile::link(rootPath, linkPath)) {
        qDebug() << "[ERROR]" << __PRETTY_FUNCTION__ << "cannot link" << linkPath << "->" << rootPath;
        return false;
    }
    qDebug() << "[ INFO ]" << __PRETTY_FUNCTION__ << "module" << uri << "->" << rootPath;
    return true;
}
