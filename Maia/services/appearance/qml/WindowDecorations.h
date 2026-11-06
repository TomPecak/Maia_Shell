#pragma once

// The window decorations for QML: the themes as a list model, the chosen one, and the commands.
//
//   import Maia.Appearance
//   WindowDecorations { id: decorations }
//   ListView {
//       model: decorations
//       delegate: ItemDelegate {
//           required property string themeId
//           required property string name
//           required property bool available
//           required property bool current
//           text: name; enabled: available; highlighted: current
//           onClicked: decorations.setTheme(themeId, result => { if (!result.ok) console.warn(result.message) })
//       }
//   }
//
// Any number of instances; they share the process's connection to the appearance service.
// Callbacks get { ok, error, message } (error: Appearance.ErrorCode), install() also the new id.

#include "AppearanceSource.h"

#include <QAbstractListModel>
#include <QJSValue>
#include <QtQml/qqmlregistration.h>

namespace MaiaAppearance {

class WindowDecorations : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    // The appearance service answers
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // "kwin", later "wayfire"
    Q_PROPERTY(QString compositor READ compositor NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool borderSizesSupported READ borderSizesSupported NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool installSupported READ installSupported NOTIFY capabilitiesChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    // The chosen theme ("" while unknown) and its shown name
    Q_PROPERTY(QString currentThemeId READ currentThemeId NOTIFY currentChanged)
    Q_PROPERTY(QString currentName READ currentName NOTIFY currentChanged)
    Q_PROPERTY(MaiaAppearance::Appearance::BorderSize borderSize READ borderSize NOTIFY currentChanged)
    // The compositor reported that it uses the chosen theme
    Q_PROPERTY(bool confirmed READ confirmed NOTIFY currentChanged)
    // The frontend whose choice it is ("" when none is active)
    Q_PROPERTY(QString frontend READ frontend NOTIFY currentChanged)

public:
    enum Role {
        ThemeIdRole = Qt::UserRole + 1,
        NameRole,
        DescriptionRole,
        AuthorRole,
        EngineRole,             // Appearance.Engine
        OriginRole,             // Appearance.Origin
        AvailableRole,          // the compositor draws it
        UnavailableReasonRole,
        RemovableRole,          // installed by the user and not in use
        CurrentRole,
        PathRole,
    };
    Q_ENUM(Role)

    explicit WindowDecorations(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool available() const;
    QString compositor() const;
    bool borderSizesSupported() const;
    bool installSupported() const;
    QString currentThemeId() const;
    QString currentName() const;
    Appearance::BorderSize borderSize() const;
    bool confirmed() const;
    QString frontend() const;

    // Uses a theme; the callback gets the result once the compositor took it (or did not)
    Q_INVOKABLE void setTheme(const QString &themeId, const QJSValue &callback = {});
    Q_INVOKABLE void setBorderSize(MaiaAppearance::Appearance::BorderSize size, const QJSValue &callback = {});
    // A directory or an archive (path or file:// URL); callback(result, themeId). Nothing is chosen.
    Q_INVOKABLE void install(const QString &pathOrUrl, const QJSValue &callback = {});
    Q_INVOKABLE void remove(const QString &themeId, const QJSValue &callback = {});
    Q_INVOKABLE void refresh();
    // The values of one theme as an object (role names as keys), {} when there is none
    Q_INVOKABLE QVariantMap get(const QString &themeId) const;

Q_SIGNALS:
    void availableChanged();
    void capabilitiesChanged();
    void countChanged();
    void currentChanged();

private:
    void resetThemes();
    void currentUpdated();

    AppearanceSource *m_source;
    QList<ThemeData> m_themes;
    QString m_current;
};

} // namespace MaiaAppearance
