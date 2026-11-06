#include "WindowDecorations.h"

#include <QJSEngine>
#include <QPointer>
#include <QUrl>

namespace MaiaAppearance {

namespace {

// A JavaScript callback for a command: called with { ok, error, message } and the extra values
AppearanceSource::Callback jsCallback(QObject *owner, const QJSValue &callback)
{
    if (!callback.isCallable())
        return {};
    return [owner = QPointer<QObject>(owner), callback](const Result &result) mutable {
        QJSEngine *engine = owner ? qjsEngine(owner) : nullptr;
        if (!engine)
            return;
        QJSValue object = engine->newObject();
        object.setProperty(QStringLiteral("ok"), result.error == Appearance::ErrorCode::None);
        object.setProperty(QStringLiteral("error"), int(result.error));
        object.setProperty(QStringLiteral("message"), result.message);
        callback.call({object});
    };
}

} // namespace

WindowDecorations::WindowDecorations(QObject *parent)
    : QAbstractListModel(parent)
    , m_source(AppearanceSource::instance())
{
    connect(m_source, &AppearanceSource::connectedChanged, this, &WindowDecorations::availableChanged);
    connect(m_source, &AppearanceSource::capabilitiesChanged, this, &WindowDecorations::capabilitiesChanged);
    connect(m_source, &AppearanceSource::themesChanged, this, &WindowDecorations::resetThemes);
    connect(m_source, &AppearanceSource::currentChanged, this, &WindowDecorations::currentUpdated);
    m_themes = m_source->themes();
    m_current = m_source->current().themeId;
}

void WindowDecorations::resetThemes()
{
    // The list is short and changes rarely (install, remove): a reset is enough
    const auto before = m_themes.size();
    beginResetModel();
    m_themes = m_source->themes();
    endResetModel();
    if (before != m_themes.size())
        Q_EMIT countChanged();
    Q_EMIT currentChanged(); // currentName may change with the list
}

void WindowDecorations::currentUpdated()
{
    const QString previous = m_current;
    m_current = m_source->current().themeId;
    if (previous != m_current) {
        for (int row = 0; row < m_themes.size(); ++row) {
            if (m_themes[row].id == previous || m_themes[row].id == m_current)
                Q_EMIT dataChanged(index(row), index(row), {CurrentRole, RemovableRole});
        }
    }
    Q_EMIT currentChanged();
}

int WindowDecorations::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_themes.size());
}

QVariant WindowDecorations::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid))
        return {};
    const ThemeData &theme = m_themes.at(index.row());
    switch (role) {
    case ThemeIdRole:
        return theme.id;
    case Qt::DisplayRole:
    case NameRole:
        return theme.name;
    case DescriptionRole:
        return theme.description;
    case AuthorRole:
        return theme.author;
    case EngineRole:
        return QVariant::fromValue(theme.engine);
    case OriginRole:
        return QVariant::fromValue(theme.origin);
    case AvailableRole:
        return theme.available;
    case UnavailableReasonRole:
        return theme.unavailableReason;
    case RemovableRole:
        return theme.origin == Appearance::Origin::User && theme.id != m_current;
    case CurrentRole:
        return theme.id == m_current;
    case PathRole:
        return theme.path;
    }
    return {};
}

QHash<int, QByteArray> WindowDecorations::roleNames() const
{
    return {{ThemeIdRole, "themeId"},
            {NameRole, "name"},
            {DescriptionRole, "description"},
            {AuthorRole, "author"},
            {EngineRole, "engine"},
            {OriginRole, "origin"},
            {AvailableRole, "available"},
            {UnavailableReasonRole, "unavailableReason"},
            {RemovableRole, "removable"},
            {CurrentRole, "current"},
            {PathRole, "path"}};
}

bool WindowDecorations::available() const
{
    return m_source->isConnected();
}

QString WindowDecorations::compositor() const
{
    return m_source->capabilities().compositor;
}

bool WindowDecorations::borderSizesSupported() const
{
    return m_source->capabilities().borderSizes;
}

bool WindowDecorations::installSupported() const
{
    return m_source->capabilities().install;
}

QString WindowDecorations::currentThemeId() const
{
    return m_current;
}

QString WindowDecorations::currentName() const
{
    const ThemeData *theme = m_source->theme(m_current);
    return theme ? theme->name : QString();
}

Appearance::BorderSize WindowDecorations::borderSize() const
{
    return m_source->current().borderSize;
}

bool WindowDecorations::confirmed() const
{
    return m_source->current().confirmed;
}

QString WindowDecorations::frontend() const
{
    return m_source->current().frontend;
}

void WindowDecorations::setTheme(const QString &themeId, const QJSValue &callback)
{
    m_source->setTheme(themeId, jsCallback(this, callback));
}

void WindowDecorations::setBorderSize(Appearance::BorderSize size, const QJSValue &callback)
{
    m_source->setBorderSize(size, jsCallback(this, callback));
}

void WindowDecorations::install(const QString &pathOrUrl, const QJSValue &callback)
{
    const QUrl url(pathOrUrl);
    const QString path = url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
    auto done = jsCallback(this, callback);
    m_source->install(path, [this, callback, done](const Result &result, const QString &themeId) mutable {
        if (!callback.isCallable())
            return;
        QJSEngine *engine = qjsEngine(this);
        if (!engine)
            return;
        QJSValue object = engine->newObject();
        object.setProperty(QStringLiteral("ok"), result.error == Appearance::ErrorCode::None);
        object.setProperty(QStringLiteral("error"), int(result.error));
        object.setProperty(QStringLiteral("message"), result.message);
        callback.call({object, themeId});
    });
}

void WindowDecorations::remove(const QString &themeId, const QJSValue &callback)
{
    m_source->remove(themeId, jsCallback(this, callback));
}

void WindowDecorations::refresh()
{
    m_source->refresh();
}

QVariantMap WindowDecorations::get(const QString &themeId) const
{
    for (int row = 0; row < m_themes.size(); ++row) {
        if (m_themes[row].id != themeId)
            continue;
        QVariantMap values;
        const auto names = roleNames();
        for (auto it = names.cbegin(); it != names.cend(); ++it)
            values.insert(QString::fromUtf8(it.value()), data(index(row), it.key()));
        return values;
    }
    return {};
}

} // namespace MaiaAppearance
