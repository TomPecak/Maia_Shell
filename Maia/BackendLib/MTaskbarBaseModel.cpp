#include "MTaskbarBaseModel.hpp"

#include <KX11Extras>
#include <kwindowinfo.h>

static bool isTaskbarEntry(const KWindowInfo &info)
{
    const NET::WindowType winType = info.windowType(NET::AllTypesMask);
    const NET::States winState = info.state();

    //why winType == 0 ? , because not all clients set window type, so clients without set window type we treat as normal window
    const bool isNormalType = (winType & NET::Normal) || (winType & NET::Dialog) || (winType == 0);
    const bool isSkipped = (winState & NET::SkipTaskbar);
    //qDebug() << "Stop: " << __PRETTY_FUNCTION__;
    return isNormalType && !isSkipped;
}

static bool isTaskbarEntry(WId id)
{
    KWindowInfo info(id, NET::WMWindowType | NET::WMState);
    if (!info.valid()) {
        return false;
    }
    return isTaskbarEntry(info);
}

MTaskbarModel::MTaskbarModel(QObject *parent)
    : QAbstractListModel(parent)
{
    initWindowList();
    initActiveWindow();

    connect(KX11Extras::self(),
            &KX11Extras::activeWindowChanged,
            this,
            &MTaskbarModel::setActiveWindow);
    connect(KX11Extras::self(), &KX11Extras::windowAdded, this, &MTaskbarModel::addItem);
    connect(KX11Extras::self(), &KX11Extras::windowRemoved, this, &MTaskbarModel::removeItem);

    connect(KX11Extras::self(),
            &KX11Extras::windowChanged,
            this,
            [this](WId id, NET::Properties properties, NET::Properties2 properties2) {
                // Check if the window is in our model at all
                int rowIndex = -1;
                for (int i = 0; i < m_items.count(); ++i) {
                    if (m_items[i].id == id) {
                        rowIndex = i;
                        break;
                    }
                }
                const bool isCurrentlyInModel = (rowIndex != -1);

                // --- Handle window state change ---
                if (properties & NET::WMState) {
                    //qDebug() << "Window STATE changed for WId:" << id;

                    const bool shouldBeInModel = isTaskbarEntry(id);

                    if (shouldBeInModel && !isCurrentlyInModel) {
                        // Window should be on the taskbar but isn't -> add it
                        qDebug() << "Window should be on taskbar, adding it:" << id;
                        addItem(id);
                    } else if (!shouldBeInModel && isCurrentlyInModel) {
                        // Window should not be on the taskbar but is -> remove it
                        qDebug() << "Window should NOT be on taskbar, removing it:" << id;
                        removeItem(id);
                    }
                }

                // If the window is not in the model, there's no need to update its name/type
                if (!isCurrentlyInModel) {
                    return;
                }

                // Updates for windows already in the model
                KWindowInfo info(id, NET::WMWindowType | NET::WMVisibleName);
                if (!info.valid()) {
                    return;
                }

                if (properties & NET::WMWindowType) {
                    qDebug() << "Window TYPE changed for WId:" << id;
                    updateWindowType(id, info.windowType(NET::AllTypesMask));
                }

#warning \
    "There is problem with NET::WMVisibleName value, there is difference in value in KF6 and KF5 library version, I dont know how to solve this by now"
                if (properties & 0x8000) { //KWindowSystem 5
                    //if (properties & NET::WMVisibleName) { //KWindowSystem 6
                    qDebug() << "Window NAME changed for WId:" << id;
                    updateWindowName(id, info.visibleName());
                }
            });
}

MTaskbarModel::~MTaskbarModel() {}

int MTaskbarModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent);
    return m_items.count();
}

QVariant MTaskbarModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.count())
        return QVariant();

    const ListItem &item = m_items[index.row()];

    switch (role) {
    case WindowNameRole:
        return item.text;
    case WindowIconRole:
        return item.imageSource;
    case WindowIdRole:
        return item.id;
    case WindowActiveRole:
        return item.windowActive;
    case WindowTypeRole:
        return static_cast<int>(item.windowType);
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> MTaskbarModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[WindowNameRole] = "windowName";
    roles[WindowIconRole] = "windowIcon";
    roles[WindowIdRole] = "windowId";
    roles[WindowActiveRole] = "windowActive";
    roles[WindowTypeRole] = "windowType";
    return roles;
}

void MTaskbarModel::addItem(const WId id)
{
    // check for duplicates
    for (const auto &item : m_items) {
        if (item.id == id) {
            return;
        }
    }

    KWindowInfo info(id, NET::WMWindowType | NET::WMVisibleName | NET::WMState);
    if (!info.valid()) {
        return;
    }

    //check if it is taskbar window
    if (!isTaskbarEntry(info)) {
        return;
    }

    NET::WindowType type = info.windowType(NET::AllTypesMask);
    QUrl imageUrl = QUrl(QString("image://backendtaskbaricons/") + QString::number(id));

    beginInsertRows(QModelIndex(), rowCount(), rowCount());
    m_items.append({id, info.visibleName(), imageUrl, false, type});
    endInsertRows();
}

void MTaskbarModel::removeItem(const WId id)
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i].id == id) {
            beginRemoveRows(QModelIndex(), i, i);
            m_items.removeAt(i);
            endRemoveRows();
            return;
        }
    }
}

void MTaskbarModel::initWindowList()
{
    QList<WId> windows = KX11Extras::windows();
    for (WId wId : windows) {
        addItem(wId);
    }
}

void MTaskbarModel::initActiveWindow()
{
    setActiveWindow(KX11Extras::activeWindow());
}

void MTaskbarModel::setActiveWindow(WId newActiveWindow)
{
    for (int i = 0; i < m_items.size(); ++i) {
        bool wasActive = m_items[i].windowActive;
        bool shouldBeActive = (m_items[i].id == newActiveWindow);
        if (wasActive != shouldBeActive) {
            m_items[i].windowActive = shouldBeActive;
            QModelIndex index = createIndex(i, 0);
            emit dataChanged(index, index, {WindowActiveRole});
        }
    }
}

void MTaskbarModel::updateWindowName(WId id, const QString &newName)
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i].id == id && m_items[i].text != newName) {
            m_items[i].text = newName;
            QModelIndex index = createIndex(i, 0);
            emit dataChanged(index, index, {WindowNameRole});
            break;
        }
    }
}

void MTaskbarModel::updateWindowType(WId id, NET::WindowType newType)
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items[i].id == id && m_items[i].windowType != newType) {
            m_items[i].windowType = newType;
            QModelIndex index = createIndex(i, 0);
            emit dataChanged(index, index, {WindowTypeRole});
            break;
        }
    }
}
