#include "SettingsPages.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QSet>

#include <algorithm>

namespace {

QStringList s_directories;
QString s_formFactor = QStringLiteral("desktop");

// "name[pl_PL]", then "name[pl]", then "name"
QJsonValue localized(const QJsonObject &object, const QString &key)
{
    const QString locale = QLocale().name();
    const QString language = locale.section(QLatin1Char('_'), 0, 0);
    for (const QString &suffix : {locale, language}) {
        const QJsonValue value = object.value(key + QLatin1Char('[') + suffix + QLatin1Char(']'));
        if (!value.isUndefined())
            return value;
    }
    return object.value(key);
}

QString fold(const QString &text)
{
    // Case and accents do not matter in a search ("siec" finds "sieć")
    QString folded;
    for (const QChar c : text.normalized(QString::NormalizationForm_D)) {
        if (c.category() != QChar::Mark_NonSpacing)
            folded.append(c.toLower());
    }
    return folded;
}

} // namespace

SettingsPages::SettingsPages(QObject *parent)
    : QAbstractListModel(parent)
    , m_pages(scan(s_directories, s_formFactor))
{
}

void SettingsPages::setDirectories(const QStringList &directories)
{
    s_directories = directories;
}

void SettingsPages::setFormFactor(const QString &formFactor)
{
    s_formFactor = formFactor;
}

QList<SettingsPages::Page> SettingsPages::scan(const QStringList &directories, const QString &formFactor)
{
    QList<Page> pages;
    QSet<QString> seen;
    for (const QString &directory : directories) {
        const QDir dir(directory);
        for (const QString &name : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
            QFile file(dir.filePath(name + QStringLiteral("/metadata.json")));
            if (!file.open(QIODevice::ReadOnly))
                continue;
            QJsonParseError error;
            const QJsonObject json = QJsonDocument::fromJson(file.readAll(), &error).object();
            if (error.error != QJsonParseError::NoError) {
                qWarning() << "[Maia Settings]" << file.fileName() << error.errorString();
                continue;
            }
            Page page;
            page.id = json.value(QStringLiteral("id")).toString(name);
            const QJsonArray formFactors = json.value(QStringLiteral("formFactors")).toArray();
            if (seen.contains(page.id) || (!formFactors.isEmpty() && !formFactors.contains(formFactor)))
                continue;
            const QString main = json.value(QStringLiteral("main")).toString();
            if (main.isEmpty() || !dir.exists(name + QLatin1Char('/') + main)) {
                qWarning() << "[Maia Settings]" << file.fileName() << "names no main QML file";
                continue;
            }
            page.name = localized(json, QStringLiteral("name")).toString(page.id);
            page.description = localized(json, QStringLiteral("description")).toString();
            page.icon = json.value(QStringLiteral("icon")).toString();
            page.order = json.value(QStringLiteral("order")).toInt(100);
            const QString localKeywords = QStringLiteral("keywords[") + QLocale().name().section(QLatin1Char('_'), 0, 0) + QLatin1Char(']');
            for (const QString &key : {QStringLiteral("keywords"), localKeywords}) {
                for (const QJsonValue &keyword : json.value(key).toArray())
                    page.keywords.append(keyword.toString());
            }
            page.source = QUrl::fromLocalFile(QDir(dir.filePath(name)).absoluteFilePath(main));
            seen.insert(page.id);
            pages.append(page);
        }
    }
    std::stable_sort(pages.begin(), pages.end(), [](const Page &a, const Page &b) { return a.order < b.order; });
    return pages;
}

int SettingsPages::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_pages.size());
}

QVariant SettingsPages::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid))
        return {};
    const Page &page = m_pages.at(index.row());
    switch (role) {
    case PageIdRole:
        return page.id;
    case Qt::DisplayRole:
    case NameRole:
        return page.name;
    case DescriptionRole:
        return page.description;
    case IconRole:
        return page.icon;
    case KeywordsRole:
        return page.keywords;
    case SourceRole:
        return page.source;
    }
    return {};
}

QHash<int, QByteArray> SettingsPages::roleNames() const
{
    return {{PageIdRole, "pageId"},   {NameRole, "name"},         {DescriptionRole, "description"},
            {IconRole, "iconName"}, {KeywordsRole, "keywords"}, {SourceRole, "source"}};
}

int SettingsPages::indexOf(const QString &id) const
{
    for (int i = 0; i < m_pages.size(); ++i) {
        if (m_pages[i].id == id)
            return i;
    }
    return -1;
}

QVariantMap SettingsPages::get(int row) const
{
    if (row < 0 || row >= m_pages.size())
        return {};
    const Page &page = m_pages.at(row);
    return {{QStringLiteral("pageId"), page.id},       {QStringLiteral("name"), page.name},
            {QStringLiteral("description"), page.description}, {QStringLiteral("iconName"), page.icon},
            {QStringLiteral("source"), page.source}};
}

bool SettingsPages::matches(int row, const QString &query) const
{
    if (row < 0 || row >= m_pages.size())
        return false;
    const Page &page = m_pages.at(row);
    const QString haystack = fold(page.name + QLatin1Char(' ') + page.description + QLatin1Char(' ') + page.keywords.join(QLatin1Char(' ')));
    const QStringList words = fold(query).split(QLatin1Char(' '), Qt::SkipEmptyParts);
    return std::all_of(words.begin(), words.end(), [&](const QString &word) { return haystack.contains(word); });
}
