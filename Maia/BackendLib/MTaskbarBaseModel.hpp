#pragma once

#include <QAbstractListModel>
#include <QImage>
#include <QUrl>
#include <QList>
#include <qqml.h>

#include <kwindowinfo.h>

class MTaskbarModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    struct ListItem {
        WId id;
        QString text;
        QUrl imageSource;
        bool windowActive;
        NET::WindowType windowType;
    };

public:
    enum ItemRoles {
        WindowNameRole = Qt::UserRole + 1,
        WindowIconRole,
        WindowIdRole,
        WindowActiveRole,
        WindowTypeRole
    };

    explicit MTaskbarModel(QObject *parent = nullptr);
    ~MTaskbarModel();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    void addItem(const WId id);
    void addItemImpl(const WId id, const QString &text, const QUrl &image, NET::WindowType type);
    void removeItem(const WId id);
    void initWindowList();
    void initActiveWindow();
    void setActiveWindow(WId newActiveWindow);
    void updateWindowName(WId id, const QString &newName);
    void updateWindowType(WId id, NET::WindowType newType);

private:
    QList<ListItem> m_items;
};
