#pragma once

#include <vector>

#include <QQmlEngine>
#include <QAbstractListModel>

class ThemesModel : public QAbstractListModel{
    Q_OBJECT
    QML_ELEMENT
    struct Theme {
        QString themeId;
        QString themeName;
        bool themeActive = false;

        bool operator==(const Theme& other) const {
            return themeId == other.themeId;
        }
    };
public:
    enum ThemeRoles {
        ThemeIdRole = Qt::UserRole + 1,
        ThemeNameRole,
        ThemeActiveRole
    };

    ThemesModel(QObject* parent = nullptr);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void setActiveFrontend(const QString& themeId);
private:
    std::vector<Theme> themes;
    void initializeThemes();
};
