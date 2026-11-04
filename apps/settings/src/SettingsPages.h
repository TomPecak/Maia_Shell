#pragma once

// The pages of Maia Settings, found at run time (a singleton for QML: Pages).
//
// A page is a directory <pages dir>/<id>/ with metadata.json:
//
//   { "id": "network", "name": "Wi-Fi", "name[pl]": "Wi-Fi",
//     "description": "Networks, hotspot, saved networks", "description[pl]": "...",
//     "icon": "network-wireless-signal-excellent-symbolic", "order": 10,
//     "keywords": ["wifi", "wlan", ...], "keywords[pl]": ["sieć", ...],
//     "main": "WifiPage.qml", "formFactors": ["desktop"] }
//
// Pages directories, the first one wins for an id: $MAIA_SETTINGS_PAGES_PATH (colon separated,
// for development), then <datadir>/maia-settings/pages of every XDG data directory, then the
// installation's own. Pages for another form factor are left out.

#include <QAbstractListModel>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class SettingsPages : public QAbstractListModel
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Pages)
    QML_SINGLETON

    Q_PROPERTY(int count READ rowCount CONSTANT)

public:
    enum Role { PageIdRole = Qt::UserRole + 1, NameRole, DescriptionRole, IconRole, KeywordsRole, SourceRole };
    Q_ENUM(Role)

    struct Page {
        QString id;
        QString name;
        QString description;
        QString icon;
        QStringList keywords;
        QUrl source;
        int order = 100;
    };

    explicit SettingsPages(QObject *parent = nullptr);

    // Set by main() before the engine creates the singleton
    static void setDirectories(const QStringList &directories);
    static void setFormFactor(const QString &formFactor);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE int indexOf(const QString &id) const;
    Q_INVOKABLE QVariantMap get(int row) const;
    // Whether a page matches a search: every word is found in its name, description or keywords
    Q_INVOKABLE bool matches(int row, const QString &query) const;

    static QList<Page> scan(const QStringList &directories, const QString &formFactor);

private:
    QList<Page> m_pages;
};
