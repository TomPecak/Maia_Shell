#include "MKdeColorScheme.hpp"

#include <QColor>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDir>
#include <QFile>
#include <QSettings>
#include <QStandardPaths>

#include <KConfig>
#include <KConfigGroup>

namespace {

// Keys in the Maia settings which remember the color scheme of the user before the first apply()
const QString previousSavedKey = QStringLiteral("KdeColorScheme/previousSaved");
const QString previousSchemeKey = QStringLiteral("KdeColorScheme/previousScheme");
const QString previousAccentKey = QStringLiteral("KdeColorScheme/previousAccentColor");

using ConfigChanges = QHash<QString, QByteArrayList>;

// Colors are written in the KDE format "r,g,b", other values as they are
QString toKdeValue(const QVariant &value)
{
    if (value.metaType().id() == QMetaType::QColor) {
        const QColor color = value.value<QColor>();
        return QStringLiteral("%1,%2,%3").arg(color.red()).arg(color.green()).arg(color.blue());
    }
    return value.toString();
}

// Groups of kdeglobals which belong to the color scheme
bool isColorGroup(const QString &name)
{
    return name.startsWith(QLatin1String("Colors:")) || name.startsWith(QLatin1String("ColorEffects:"))
           || name == QLatin1String("WM");
}

// Plasma stores the hash of the scheme file to detect changes of the scheme
QString fileHash(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromLatin1(QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha1).toHex());
}

} // namespace

MKdeColorScheme::MKdeColorScheme(QObject *parent)
    : QObject(parent)
{
    qDBusRegisterMetaType<ConfigChanges>();
}

QString MKdeColorScheme::currentScheme() const
{
    KConfig globals(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);
    return globals.group(QStringLiteral("General")).readEntry("ColorScheme", QString());
}

bool MKdeColorScheme::apply(const QString &id, const QString &name, const QVariantMap &groups)
{
    if (id.isEmpty() || groups.isEmpty()) {
        qDebug() << "[ERROR] MKdeColorScheme::apply(): empty scheme id or groups";
        return false;
    }

    rememberPreviousScheme();

    // Write the scheme file
    const QString dirPath = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                            + QStringLiteral("/color-schemes");
    QDir().mkpath(dirPath);
    const QString filePath = dirPath + QLatin1Char('/') + id + QStringLiteral(".colors");
    QFile::remove(filePath);

    {
        KConfig scheme(filePath, KConfig::SimpleConfig);
        for (auto group = groups.cbegin(); group != groups.cend(); ++group) {
            KConfigGroup configGroup = scheme.group(group.key());
            const QVariantMap entries = group.value().toMap();
            for (auto entry = entries.cbegin(); entry != entries.cend(); ++entry)
                configGroup.writeEntry(entry.key(), toKdeValue(entry.value()));
        }

        KConfigGroup general = scheme.group(QStringLiteral("General"));
        general.writeEntry("ColorScheme", id);
        general.writeEntry("Name", name);

        if (!scheme.sync()) {
            qDebug() << "[ERROR] MKdeColorScheme::apply(): can not write" << filePath;
            return false;
        }
    }

    if (!applySchemeFile(id, filePath))
        return false;

    // A custom accent color of the user would override the accent of the scheme
    KConfig globals(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);
    KConfigGroup general = globals.group(QStringLiteral("General"));
    if (general.hasKey("AccentColor")) {
        general.deleteEntry("AccentColor");
        globals.sync();
    }

    notifyApplications();
    Q_EMIT currentSchemeChanged();
    return true;
}

bool MKdeColorScheme::restorePrevious()
{
    QSettings settings;
    if (!settings.value(previousSavedKey, false).toBool())
        return false;

    const QString previousScheme = settings.value(previousSchemeKey).toString();
    const QString previousAccent = settings.value(previousAccentKey).toString();

    const QString filePath = previousScheme.isEmpty()
                                 ? QString()
                                 : QStandardPaths::locate(QStandardPaths::GenericDataLocation,
                                                          QStringLiteral("color-schemes/") + previousScheme
                                                              + QStringLiteral(".colors"));

    if (!filePath.isEmpty()) {
        applySchemeFile(previousScheme, filePath);
    } else {
        // No scheme was set (KDE defaults) or its file is gone: remove the colors of the scheme
        KConfig globals(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);
        const QStringList groupNames = globals.groupList();
        for (const QString &group : groupNames) {
            if (isColorGroup(group))
                globals.deleteGroup(group);
        }
        KConfigGroup general = globals.group(QStringLiteral("General"));
        general.deleteEntry("ColorScheme");
        general.deleteEntry("ColorSchemeHash");
        globals.sync();
    }

    if (!previousAccent.isEmpty()) {
        KConfig globals(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);
        globals.group(QStringLiteral("General")).writeEntry("AccentColor", previousAccent);
        globals.sync();
    }

    // The next apply() remembers the scheme of the user again
    settings.remove(previousSavedKey);
    settings.remove(previousSchemeKey);
    settings.remove(previousAccentKey);

    notifyApplications();
    Q_EMIT currentSchemeChanged();
    return true;
}

void MKdeColorScheme::rememberPreviousScheme()
{
    QSettings settings;
    if (settings.value(previousSavedKey, false).toBool())
        return;

    KConfig globals(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);
    const KConfigGroup general = globals.group(QStringLiteral("General"));
    settings.setValue(previousSchemeKey, general.readEntry("ColorScheme", QString()));
    settings.setValue(previousAccentKey, general.readEntry("AccentColor", QString()));
    settings.setValue(previousSavedKey, true);
}

bool MKdeColorScheme::applySchemeFile(const QString &id, const QString &filePath)
{
    KConfig scheme(filePath, KConfig::SimpleConfig);
    KConfig globals(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);

    // Remove the colors of the previous scheme, so none of them stays
    const QStringList oldGroups = globals.groupList();
    for (const QString &group : oldGroups) {
        if (isColorGroup(group))
            globals.deleteGroup(group);
    }

    // Copy the color groups of the scheme (with subgroups, e.g. [Colors:Header][Inactive])
    const QStringList schemeGroups = scheme.groupList();
    for (const QString &group : schemeGroups) {
        if (!isColorGroup(group))
            continue;
        KConfigGroup target = globals.group(group);
        scheme.group(group).copyTo(&target);
    }

    KConfigGroup general = globals.group(QStringLiteral("General"));
    general.writeEntry("ColorScheme", id);
    general.writeEntry("ColorSchemeHash", fileHash(filePath));

    if (!globals.sync()) {
        qDebug() << "[ERROR] MKdeColorScheme: can not write kdeglobals";
        return false;
    }
    return true;
}

void MKdeColorScheme::notifyApplications()
{
    QDBusConnection bus = QDBusConnection::sessionBus();

    // Qt applications with the KDE platform theme reload the palette (KGlobalSettings::PaletteChanged)
    QDBusMessage paletteChanged = QDBusMessage::createSignal(QStringLiteral("/KGlobalSettings"),
                                                             QStringLiteral("org.kde.KGlobalSettings"),
                                                             QStringLiteral("notifyChange"));
    paletteChanged << 0 << 0;
    bus.send(paletteChanged);

    // KConfigWatcher of kdeglobals (used e.g. by KWin for window decoration colors)
    ConfigChanges changes;
    changes.insert(QStringLiteral("General"), {QByteArrayLiteral("ColorScheme")});
    QDBusMessage configChanged = QDBusMessage::createSignal(QStringLiteral("/kdeglobals"),
                                                            QStringLiteral("org.kde.kconfig.notify"),
                                                            QStringLiteral("ConfigChanged"));
    configChanged << QVariant::fromValue(changes);
    bus.send(configChanged);
}
