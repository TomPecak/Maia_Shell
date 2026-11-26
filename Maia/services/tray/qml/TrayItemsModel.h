#pragma once

// TrayItemsModel: the items of the system tray, for a shell to draw. Which ones it holds is the
// shell's choice (filter, maximumCount); the order and the rule that attention wins are the
// model's, so every shell gets them alike:
//
//   TrayItemsModel { id: plate; filter: TrayItemsModel.Shown; maximumCount: 4 }
//   Repeater { model: plate; delegate: Icon { source: model.currentIconSource } }
//   Text { text: "+" + (Tray.count - plate.count) }
//
// - Order: by category (applications, communications, system services, hardware, as the
//   specification lists them), then by when the item came. A change of status never moves an item.
// - maximumCount: items that need attention are taken first, then the others in order; the rows
//   are still in order. hiddenCount: the items of the filter left out.
// - Icons: *IconSource is what to give an Image or Kirigami.Icon: the theme's icon when the theme
//   has it, otherwise the item's image (pixels, a file of the application's own directory).
//   currentIconSource is the icon to show now (the attention icon while it needs attention).
//
// Updates tell only the roles that changed, once per batch of the service.

#include "TrayData.h"

#include <QAbstractListModel>
#include <QList>
#include <QtQml/qqmlregistration.h>

namespace MaiaTray {

class TrayItemsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(Filter filter READ filter WRITE setFilter NOTIFY filterChanged)
    // -1: all of the filter
    Q_PROPERTY(int maximumCount READ maximumCount WRITE setMaximumCount NOTIFY maximumCountChanged)
    Q_PROPERTY(int hiddenCount READ hiddenCount NOTIFY hiddenCountChanged)
    // Rows that need attention
    Q_PROPERTY(int attentionCount READ attentionCount NOTIFY attentionCountChanged)

public:
    enum Filter {
        All,     // every item
        Shown,   // active and needing attention: what a tray shows by itself
        Passive, // the rest: what goes into an overflow
    };
    Q_ENUM(Filter)

    enum Role {
        ItemIdRole = Qt::UserRole + 1,
        KeyRole,
        TitleRole,
        StatusRole,
        CategoryRole,
        NeedsAttentionRole,
        IconNameRole,
        IconUrlRole,
        IconSourceRole,
        AttentionIconSourceRole,
        OverlayIconSourceRole,
        CurrentIconSourceRole,
        ToolTipTitleRole,
        ToolTipTextRole,
        ToolTipIconSourceRole,
        HasMenuRole,
        ItemIsMenuRole,
        DesktopEntryRole,
        AppNameRole,
        AppIconRole,
    };
    Q_ENUM(Role)

    explicit TrayItemsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Filter filter() const { return m_filter; }
    void setFilter(Filter filter);
    int maximumCount() const { return m_maximumCount; }
    void setMaximumCount(int count);
    int hiddenCount() const { return m_hiddenCount; }
    int attentionCount() const { return m_attentionCount; }

    // The item of a row, as a map of its roles (for a menu or a tool tip outside the delegate)
    Q_INVOKABLE QVariantMap get(int row) const;

    // The rows a model of `filter` and `maximumCount` holds, in their order (tests, other models)
    static QList<ItemData> select(const QList<ItemData> &items, Filter filter, int maximumCount, int *hidden = nullptr);
    // The source to give an Image or Kirigami.Icon for an icon
    static QString iconSource(const IconData &icon);

Q_SIGNALS:
    void countChanged();
    void filterChanged();
    void maximumCountChanged();
    void hiddenCountChanged();
    void attentionCountChanged();

private:
    void refresh();
    static QList<int> changedRoles(const ItemData &before, const ItemData &after);

    QList<ItemData> m_rows;
    Filter m_filter = All;
    int m_maximumCount = -1;
    int m_hiddenCount = 0;
    int m_attentionCount = 0;
};

} // namespace MaiaTray
