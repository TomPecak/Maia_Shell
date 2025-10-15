#include "Backend.hpp"

#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QGuiApplication>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <QSettings>
#include <QIcon>

#include <KX11Extras>
#include <KConfig>
#include <KConfigGroup>
#include <KSharedConfig>
#include <qtconcurrentrun.h>

#include "./helper/Process.hpp"
#include "maia_version.h"

Backend::Backend(QString homeEnv, QObject *parent)
    : QObject(parent)
    , m_cpuFile("/proc/stat")
    , m_measureCpuLoad(false)
    , HOME_ENV(homeEnv)
    , mask(this)
    , strutManager(this)
{
    m_platformName = QGuiApplication::platformName();
    if (m_platformName == "xcb") {
        m_platformName = "X11";
    }
    emit platformNameChanged();

    //cpu load init
    connect(&m_timer, &QTimer::timeout, this, &Backend::updateCpuLoad);
}

Backend::~Backend()
{
    if (m_cpuFile.isOpen()) {
        m_cpuFile.close(); // Close the file in the destructor
    }
}

void Backend::installIconTheme(const QUrl &themeUrl, bool forceReinstall)
{
    // Docelowa lokalizacja: $HOME/.local/share/icons
    QString targetInstallDirPath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/icons";
    installDirInternal(themeUrl, targetInstallDirPath, forceReinstall);
}

void Backend::installAuroraeTheme(const QUrl &themeUrl, bool forceReinstall)
{
    qDebug() << __PRETTY_FUNCTION__ << themeUrl;

    // Docelowa lokalizacja: $HOME/.local/share/aurorae/themes
    QString targetInstallDirPath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/aurorae/themes";
    installDirInternal(themeUrl, targetInstallDirPath, forceReinstall);
}

void Backend::setAuroraeTheme(const QString themeName)
{
    qDebug() << "Attempting to set Aurorae theme to:" << themeName;

#warning "This operation is not asynchronous"

    // Step 1: Verify that the theme exists
    QString themePath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/aurorae/themes/" + themeName;
    QDir themeDir(themePath);
    if (!themeDir.exists()) {
        qDebug() << "Aurorae theme directory does not exist at:" << themePath;
        // Attempt to reinstall from stored URL
        QSettings settings;
        settings.beginGroup("[Installed_themes_URLs]");
        QString savedUrl = settings.value(themeName, "").toString();
        settings.endGroup();
        if (!savedUrl.isEmpty()) {
            qDebug() << "Attempting to reinstall missing Aurorae theme:" << themeName << "from URL:" << savedUrl;
            QUrl themeUrl(savedUrl);
            installAuroraeTheme(themeUrl, true); // Force reinstall
            if (!themeDir.exists()) {
                qDebug() << "[ERROR] Failed to reinstall Aurorae theme:" << themeName;
                emit themeReinstallationFailed(themeName);
                return;
            }
        } else {
            qDebug() << "[ERROR] No URL found in settings for Aurorae theme:" << themeName;
            emit themeReinstallationFailed(themeName);
            return;
        }
    }

    // Step 2: Verify metadata
    if (!themeDir.exists("metadata.desktop")) {
        qDebug() << "[ERROR] Invalid Aurorae theme: metadata.desktop not found in" << themePath;
        emit themeReinstallationFailed(themeName);
        return;
    }

    // Step 3: Update kwinrc configuration using KSharedConfig
    KSharedConfig::Ptr config = KSharedConfig::openConfig("kwinrc", KConfig::SimpleConfig);
    KConfigGroup decorationGroup(config, "org.kde.kdecoration2");
    decorationGroup.writeEntry("theme", "__aurorae__svg__" + themeName);
    decorationGroup.writeEntry("library", "org.kde.kwin.aurorae");
    if (!config->sync()) {
        qDebug() << "[ERROR] Failed to save kwinrc configuration for theme:" << themeName;
        emit themeReinstallationFailed(themeName);
        return;
    }

    qDebug() << "Successfully updated kwinrc with theme:" << themeName;
}

void Backend::setIconTheme(const QString themeName)
{
    qDebug() << "Attempting to set icon theme to:" << themeName;

#warning "This operation is not asynchronous"

    // Step 1: Verify that the theme exists
    QString themePath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/icons/" + themeName;
    QDir themeDir(themePath);
    if (!themeDir.exists()) {
        qDebug() << "Icon theme directory does not exist at:" << themePath;
        // Attempt to reinstall from stored URL
        QSettings settings;
        settings.beginGroup("[Installed_themes_URLs]");
        QString savedUrl = settings.value(themeName, "").toString();
        settings.endGroup();
        if (!savedUrl.isEmpty()) {
            qDebug() << "Attempting to reinstall missing icon theme:" << themeName << "from URL:" << savedUrl;
            QUrl themeUrl(savedUrl);
            installIconTheme(themeUrl, true); // Force reinstall
            if (!themeDir.exists()) {
                qDebug() << "[ERROR] Failed to reinstall icon theme:" << themeName;
                emit themeReinstallationFailed(themeName);
                return;
            }
        } else {
            qDebug() << "[ERROR] No URL found in settings for icon theme:" << themeName;
            emit themeReinstallationFailed(themeName);
            return;
        }
    }

    // Step 2: Apply icon theme
    QIcon::setThemeName(themeName);

    // Optional: Update kdeglobals for KDE compatibility
    KSharedConfig::Ptr config = KSharedConfig::openConfig("kdeglobals", KConfig::SimpleConfig);
    KConfigGroup iconGroup(config, "Icons");
    iconGroup.writeEntry("Theme", themeName);
    if (!config->sync()) {
        qDebug() << "[ERROR] Failed to save kdeglobals configuration for icon theme:" << themeName;
        emit themeReinstallationFailed(themeName);
        return;
    }

    qDebug() << "Successfully set icon theme to:" << themeName;
}

void Backend::setDefaultWindowDecoration()
{
    qDebug() << "Attempting to set default window decoration";

#warning "This operation is not asynchronous"

    // Step 1: Update kwinrc configuration using KSharedConfig
    KSharedConfig::Ptr config = KSharedConfig::openConfig("kwinrc", KConfig::SimpleConfig);
    KConfigGroup decorationGroup(config, "org.kde.kdecoration2");

    // Delete the entire [org.kde.kdecoration2] group to reset to default
    decorationGroup.deleteGroup();

    if (!config->sync()) {
        qDebug() << "[ERROR] Failed to save kwinrc configuration after removing [org.kde.kdecoration2]";
        return;
    }

    qDebug() << "Successfully removed [org.kde.kdecoration2] group from kwinrc to use default window decoration";
}

bool Backend::copyLocalDirectory(const QString &sourcePath, const QString &targetPath)
{
    QDir targetDir(targetPath);

    if (!targetDir.exists() && !targetDir.mkpath(".")) {
        qDebug() << "Failed to create target directory:" << targetPath;
        return false;
    }

    // Copy files
    QDirIterator fileIt(sourcePath, QDir::Files | QDir::NoDotAndDotDot);
    while (fileIt.hasNext()) {
        fileIt.next();
        QString srcFilePath = fileIt.filePath();
        QString dstFilePath = targetDir.absoluteFilePath(fileIt.fileName());
        if (!QFile::copy(srcFilePath, dstFilePath)) {
            qDebug() << "Failed to copy file:" << srcFilePath << "to" << dstFilePath;
            return false;
        }
    }

    // Copy dirs
    QDirIterator dirIt(sourcePath, QDir::Dirs | QDir::NoDotAndDotDot);
    while (dirIt.hasNext()) {
        dirIt.next();
        QString srcSubDir = dirIt.filePath();
        QString dstSubDir = targetDir.absoluteFilePath(dirIt.fileName());
        if (!copyLocalDirectory(srcSubDir, dstSubDir)) {
            return false;
        }
    }

    return true;
}

bool Backend::copyQrcDirectory(const QString &sourcePath, const QString &targetPath)
{
    QDir targetDir(targetPath);
    if (!targetDir.exists() && !targetDir.mkpath(".")) {
        qDebug() << "Failed to create target directory:" << targetPath;
        return false;
    }

    QDir qrcDir(":/" + sourcePath);
    if (!qrcDir.exists()) {
        qDebug() << "QRC directory not found:" << sourcePath;
        return false;
    }

    // Copy files
    QDirIterator fileIt(":/" + sourcePath, QDir::Files | QDir::NoDotAndDotDot);
    while (fileIt.hasNext()) {
        fileIt.next();
        QString srcFilePath = fileIt.filePath();
        QString dstFilePath = targetDir.absoluteFilePath(fileIt.fileName());
        if (!QFile::copy(srcFilePath, dstFilePath)) {
            qDebug() << "Failed to copy qrc file:" << srcFilePath << "to" << dstFilePath;
            return false;
        }
    }

    // Copy subdirectories
    QDirIterator dirIt(":/" + sourcePath, QDir::Dirs | QDir::NoDotAndDotDot);
    while (dirIt.hasNext()) {
        dirIt.next();
        QString srcSubDir = sourcePath + "/" + dirIt.fileName();
        QString dstSubDir = targetDir.absoluteFilePath(dirIt.fileName());
        if (!copyQrcDirectory(srcSubDir, dstSubDir)) {
            return false;
        }
    }

    return true;
}

void Backend::activateWindow(WId win)
{
    KX11Extras::activateWindow(win);
}

void Backend::minimalizeAllWindows()
{
    if (m_platformName == "X11") {
        const QList<WId> windows = KX11Extras::windows();
        for (const WId &windowId : windows) {
            KX11Extras::minimizeWindow(windowId);
        }
    } else {
        qDebug() << "Minimize all windows is not supported on this platform.";
    }
}

void Backend::startApplication(const QString &id) {}

void Backend::startProcess(const QString &proc)
{
    QProcess::startDetached(proc);
}

void Backend::runCommand(const QString &cmd)
{
    QStringList parts = cmd.split(' ', Qt::SkipEmptyParts);
    QString program = parts.takeFirst();
    QStringList filteredArgs;
    for (const QString &arg : parts) {
        if (!arg.startsWith('%')) {
            filteredArgs << arg;
        }
    }

    // Why do we filter environment variables? Let's assume Maia is compiled with different libraries than the application in the target system.
    // If LD_LIBRARY_PATH points to Maia's library path, the application will link to Maia's libraries instead of the system libraries.
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    filterProcessEnvironment(env, QString("/opt/Maia/Maia_") + QString(MAIA_VERSION_STRING) + QString("/lib"));

    QProcess process;
    process.setProgram(program);
    process.setArguments(filteredArgs);
    process.setProcessEnvironment(env);
    process.startDetached();
}

void Backend::reservePanelLeftArea(QQuickWindow *window, int x, int y, int width, int height)
{
    strutManager.reservePanelLeftArea(window, x, y, width, height);
}

void Backend::reservePanelRightArea(QQuickWindow *window, int x, int y, int width, int height)
{
    strutManager.reservePanelRightArea(window, x, y, width, height);
}

void Backend::reservePanelTopArea(QQuickWindow *window, int x, int y, int width, int height)
{
    strutManager.reservePanelTopArea(window, x, y, width, height);
}

void Backend::reservePanelBottomArea(QQuickWindow *window, int x, int y, int width, int height)
{
    strutManager.reservePanelBottomArea(window, x, y, width, height);
}

void Backend::setX11WindowTypeAsNormal(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::Normal);
    }
}

void Backend::setX11WindowTypeAsDesktop(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::Desktop);
    }
}

void Backend::setX11WindowTypeAsDock(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::Dock);
    }
}

void Backend::setX11WindowTypeAsToolbar(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::Toolbar);
    }
}

void Backend::setX11WindowTypeAsMenu(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::Menu);
    }
}

void Backend::setX11WindowTypeAsOverride(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::Override);
    }
}

void Backend::setX11WindowTypeAsTopMenu(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::TopMenu);
    }
}

void Backend::setX11WindowTypeAsPopupMenu(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::PopupMenu);
    }
}

void Backend::setX11WindowTypeAsNotification(QQuickWindow *window)
{
    if (window) {
        KX11Extras::setType(window->winId(), NET::WindowType::Notification);
    }
}

QString Backend::platformName() const
{
    return m_platformName;
}

QString Backend::qtVersion() const
{
    return QString(qVersion());
}

float Backend::cpuLoad() const
{
    return m_cpuLoad;
}

bool Backend::measureCpuLoad() const
{
    return m_measureCpuLoad;
}

void Backend::setMeasureCpuLoad(bool enable)
{
    if (m_measureCpuLoad == enable)
        return; // Check if the state has changed

    m_measureCpuLoad = enable;
    emit measureCpuLoadChanged();

    if (m_measureCpuLoad) {
        // Enable CPU measurement
        if (!m_cpuFile.isOpen()) {
            if (!m_cpuFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                qDebug() << "[ERROR] Unable to open /proc/stat file";
                return;
            }
        }
        m_timer.start(1000); // Start the timer
    } else {
        // Disable CPU measurement
        m_timer.stop(); // Stop the timer
        if (m_cpuFile.isOpen()) {
            m_cpuFile.close(); // Close the file
        }
    }
}

void Backend::updateCpuLoad()
{
    if (!m_cpuFile.isOpen()) {
        qDebug() << "[ERROR] /proc/stat file is not open";
        return;
    }

    // Reset the file pointer to the beginning to read new data
    m_cpuFile.seek(0);

    QTextStream in(&m_cpuFile);
    QString line = in.readLine();

    QStringList cpuData = line.split(QRegularExpression("\\s+"));
    if (cpuData.size() < 8)
        return;

    long long user = cpuData[1].toLongLong();
    long long nice = cpuData[2].toLongLong();
    long long system = cpuData[3].toLongLong();
    long long idle = cpuData[4].toLongLong();
    long long iowait = cpuData[5].toLongLong();
    long long irq = cpuData[6].toLongLong();
    long long softirq = cpuData[7].toLongLong();

    long long total = user + nice + system + idle + iowait + irq + softirq;
    long long totalIdle = idle + iowait;

    if (prevTotal != 0 && prevIdle != 0) {
        long long totalDiff = total - prevTotal;
        long long idleDiff = totalIdle - prevIdle;

        m_cpuLoad = (1.0f - (float(idleDiff) / float(totalDiff))) * 100.0f;
        emit cpuLoadChanged();
    }

    prevTotal = total;
    prevIdle = totalIdle;
}

bool Backend::installDirInternal(const QUrl &themeUrl, const QString &targetDirPath, bool forceReinstall)
{
    QDir targetDir(targetDirPath);

    if (!themeUrl.isValid()) {
        qDebug() << "Invalid theme URL:" << themeUrl;
        return false;
    }

    QString sourcePath;
    QDir sourceDir;
    if (themeUrl.scheme() == "qrc") {
        sourcePath = themeUrl.path();
        if (sourcePath.startsWith('/')) {
            sourcePath = sourcePath.mid(1); // Remove leading "/"
        }
        sourceDir.setPath(":/" + sourcePath);
    } else if (themeUrl.scheme() == "file" || themeUrl.isLocalFile()) {
        sourcePath = themeUrl.toLocalFile();
        sourceDir.setPath(sourcePath);
    } else {
        qDebug() << "Unsupported scheme in theme URL:" << themeUrl.scheme();
        return false;
    }

    if (!sourceDir.exists()) {
        qDebug() << "Source directory does not exist:" << sourcePath;
        return false;
    }

    QString themeName = sourceDir.dirName();
    QString targetThemePath = targetDirPath + "/" + themeName;
    QDir targetThemeDir(targetThemePath);


    if(forceReinstall){
        targetThemeDir.removeRecursively();
        clearInstalledUrl(themeName);
    }

    if(isUrlInstalled(themeName, targetThemePath)){
        // Check if the theme directory exists and is recorded in settings
        if(targetThemeDir.exists()){ //settings - ok ; dir - ok
            qDebug() << "Theme already installed and directory exists, skipping:" << themeName;
            return true;
        // If directory is missing but URL is in settings, clear settings to force reinstall
        }else{ //settings - ok ; dir - false
            qDebug() << "Theme directory missing but recorded in settings, clearing settings for reinstall:" << themeName;
            clearInstalledUrl(themeName);
        }
    }else{
        if(targetThemeDir.exists()){ //settings - false ; dir - ok
            qDebug() << "Theme directory exists but not recored in settings, so remove dir and reinstall";
            targetThemeDir.removeRecursively();
        }else{ //settings - false ; dir - false
            qDebug() << "Install theme, theme directory doesn't exists and not recored in settings, so install";
        }
    }


    // Copy
    if (!targetDir.exists()) {
        if (!targetDir.mkpath(".")) {
            qDebug() << "[ERROR] Failed to create target directory:" << targetDirPath;
            return false;
        }
    }

    bool success;
    if (themeUrl.scheme() == "qrc") {
        success = copyQrcDirectory(sourcePath, targetThemePath);
    } else {
        success = copyLocalDirectory(sourcePath, targetThemePath);
    }

    if (success) {
        // Save to settings
        saveInstalledUrl(themeName, targetThemePath);
        qDebug() << "Theme installed successfully and marked in settings:" << targetThemePath;
    } else {
        // Remove partial after error
        if (targetThemeDir.exists()) {
            targetThemeDir.removeRecursively();
        }
        clearInstalledUrl(themeName);
        qDebug() << "Failed to install theme from:" << sourcePath;
    }
    return success;
}

void Backend::addMaskedItem(QQuickItem *item)
{
    mask.addMaskedItem(item);
}

void Backend::removeMaskedItem(QQuickItem *item)
{
    mask.removeMaskedItem(item);
}

bool Backend::isUrlInstalled(const QString &themeName, const QUrl &themeUrl)
{
    QSettings settings;
    settings.beginGroup("[Installed_themes_URLs]");
    QString savedUrl = settings.value(themeName, "").toString();
    settings.endGroup();
    return savedUrl == themeUrl.toString();
}

void Backend::saveInstalledUrl(const QString &themeName, const QUrl &themeUrl)
{
    QSettings settings;
    settings.beginGroup("[Installed_themes_URLs]");
    settings.setValue(themeName ,themeUrl.toString());
    settings.endGroup();
    settings.sync(); // Ensure saving to disk
}

void Backend::clearInstalledUrl(const QString &themeName)
{
    QSettings settings;
    settings.beginGroup("[Installed_themes_URLs]");
    settings.remove(themeName);
    settings.endGroup();
    settings.sync();
}
