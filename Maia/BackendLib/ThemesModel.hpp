#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVector>

class ThemesModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(QString activeThemeId
               READ activeThemeId
               NOTIFY activeThemeChanged)

public:
    enum ThemeRoles {
        ThemeIdRole = Qt::UserRole + 1,
        ThemeNameRole,
        ThemeActiveRole
    };

    explicit ThemesModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index,
                  int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString activeThemeId() const;

    Q_INVOKABLE void setActiveFrontend(const QString &frontendId);
    Q_INVOKABLE void setActiveTheme(const QString &themeId);

signals:
    void activeThemeChanged();

private:
    struct Theme {
        QString themeId;
        QString themeName;
        bool themeActive;
    };

    void initializeThemes();

    QVector<Theme> themes;
    QString m_activeThemeId;
};
