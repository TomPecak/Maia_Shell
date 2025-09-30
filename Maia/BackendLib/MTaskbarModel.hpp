// #pragma once

// #include <QSortFilterProxyModel>

// #include "BTaskbarBaseModel.hpp"

// class MTaskbarModel : public QSortFilterProxyModel{
//     Q_OBJECT
//     QML_ELEMENT

//     Q_PROPERTY(bool filterDesktop READ filterDesktop WRITE setFilterDesktop NOTIFY filterDesktopChanged)
//     Q_PROPERTY(bool filterNotification READ filterNotification WRITE setFilterNotification NOTIFY filterNotificationChanged)

// public:
//     explicit MTaskbarModel(QObject *parent = nullptr);

//     bool filterDesktop() const;
//     bool setFilterDesktop(bool enabled);

//     bool filterNotification() const;
//     bool setFilterNotification(bool enabled);

// signals:
//     void filterDesktopChanged();
//     void filterNotificationChanged();

// protected:
//     bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override {
//         //qDebug() << __PRETTY_FUNCTION__;
//         QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);
//         int windowType = sourceModel()->data(index, BTaskbarBaseModel::WindowTypeRole).toInt();
//         return m_filterTypes.value(static_cast<NET::WindowType>(windowType), true);
//     }

// private:
//     BTaskbarBaseModel m_baseModel;
//     QMap<NET::WindowType, bool> m_filterTypes;
// };
