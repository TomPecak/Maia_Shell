#pragma once

// The values of the contract (../contract/tray.capnp) as plain Qt values, read in the KJ thread so
// that the GUI thread gets finished QStrings.

#include <QString>

#include <vector>

namespace MaiaTray {

// The numbers of the contract's enums (Tray.h exposes them to QML)
enum class ItemStatus { Passive = 0, Active = 1, NeedsAttention = 2 };
enum class ItemCategory { ApplicationStatus = 0, Communications = 1, SystemServices = 2, Hardware = 3 };

struct IconData {
    QString name;
    QString url;

    bool isEmpty() const { return name.isEmpty() && url.isEmpty(); }
    bool operator==(const IconData &) const = default;
};

struct ItemData {
    quint32 id = 0;
    QString key;
    QString title;
    ItemStatus status = ItemStatus::Active;
    ItemCategory category = ItemCategory::ApplicationStatus;
    IconData icon;
    IconData attentionIcon;
    IconData overlayIcon;
    QString toolTipTitle;
    QString toolTipText;
    IconData toolTipIcon;
    bool hasMenu = false;
    bool itemIsMenu = false;
    QString desktopEntry;
    QString appName;
    QString appIcon;

    bool operator==(const ItemData &) const = default;
};

// 0 none, 1 checkmark, 2 radio (the contract's Toggle)
struct MenuEntryData {
    int id = 0;
    bool separator = false;
    QString label;
    bool enabled = true;
    IconData icon;
    int toggle = 0;
    bool checked = false;
    QString shortcut;
    bool submenu = false;
    std::vector<MenuEntryData> children;

    bool operator==(const MenuEntryData &) const = default;
};

using MenuEntries = std::vector<MenuEntryData>;

} // namespace MaiaTray
