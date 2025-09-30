#include "ThemesModel.hpp"


ThemesModel::ThemesModel(QObject *parent)
    : QAbstractListModel(parent)
{
    initializeThemes();
}

void ThemesModel::initializeThemes()
{
    themes.push_back({ "Gnome", "Gnome", false });
    themes.push_back({ "Windows XP", "Windows XP", true });
}

int ThemesModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return static_cast<int>(themes.size());
}

QVariant ThemesModel::data(const QModelIndex &index, int role) const
{
    if (index.row() < 0 || index.row() >= themes.size()){
        return QVariant();
    }

    const Theme &theme = themes[index.row()];
    if (role == ThemeIdRole){
        return theme.themeId;
    }
    else if (role == ThemeNameRole){
        return theme.themeName;
    }
    else if (role == ThemeActiveRole){
        return theme.themeActive;
    }
    return QVariant();
}

QHash<int, QByteArray> ThemesModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[ThemeIdRole] = "themeId";
    roles[ThemeNameRole] = "themeName";
    roles[ThemeActiveRole] = "themeActive";
    return roles;
}

void ThemesModel::setActiveFrontend(const QString& frontendId)
{
    qDebug() << __PRETTY_FUNCTION__;

    for (size_t i = 0; i < themes.size(); ++i) {
        if (themes[i].themeId == frontendId && !themes[i].themeActive) {
            themes[i].themeActive = true;
            emit dataChanged(index(static_cast<int>(i)), index(static_cast<int>(i)), { ThemeActiveRole });
        } else if (themes[i].themeActive) {
            themes[i].themeActive = false;
            emit dataChanged(index(static_cast<int>(i)), index(static_cast<int>(i)), { ThemeActiveRole });
        }
    }
}
