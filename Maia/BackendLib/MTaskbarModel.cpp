// #include "MTaskbarModel.hpp"

// MTaskbarModel::MTaskbarModel(QObject *parent) :
//     QSortFilterProxyModel(parent),
//     m_baseModel(this)
// {
//     setSourceModel(&m_baseModel);

//     m_filterTypes[NET::Desktop] = false;
//     m_filterTypes[NET::Notification] = false;
// }

// bool MTaskbarModel::filterDesktop() const
// {
//     return m_filterTypes.value(NET::Desktop, true);
// }

// bool MTaskbarModel::setFilterDesktop(bool enabled)
// {
//     if(m_filterTypes[NET::Desktop] != enabled){
//         m_filterTypes[NET::Desktop] = enabled;
//         invalidateFilter();
//         emit filterDesktopChanged();
//     }
// }

// bool MTaskbarModel::filterNotification() const
// {
//     return m_filterTypes.value(NET::Notification, true);
// }

// bool MTaskbarModel::setFilterNotification(bool enabled)
// {
//     if(m_filterTypes[NET::Notification] != enabled){
//         m_filterTypes[NET::Notification] = enabled;
//         invalidateFilter();
//         emit filterNotificationChanged();
//     }
// }
