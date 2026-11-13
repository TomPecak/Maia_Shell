#pragma once

// The values of the notification service as plain Qt values, without Cap'n Proto: what the models
// and the connections keep. Contract.h translates them from and to the contract.
//
// The numbers of urgency and close reasons are the contract's: Normal 0, Low 1, Critical 2;
// Expired 0, Dismissed 1, ClosedByApp 2, Other 3.

#include <QList>
#include <QMetaType>
#include <QString>
#include <QStringList>

namespace MaiaNotifications {

struct ActionData {
    QString key;
    QString label;

    bool operator==(const ActionData &) const = default;
};

// What a sender asks for (Notifier.notify, NotificationHandle.update)
struct RequestData {
    QString appName;
    QString desktopEntry;
    QString appIcon;
    QString summary;
    QString body;
    QString image;
    QList<ActionData> actions;
    bool actionIcons = false;
    int urgency = 0;
    QString category;
    int timeout = -1;
    bool transient = false;
    bool resident = false;
    bool inlineReply = false;
    QString replyPlaceholder;
    QString replySubmitText;
    QString soundName;
    bool suppressSound = false;
};

// A notification as the service shows it to shells
struct NotificationData {
    quint32 id = 0;
    QString appName;
    QString desktopEntry;
    QString appIcon;
    QString summary;
    QString body;
    QString image;
    QList<ActionData> actions;
    bool actionIcons = false;
    int urgency = 0;
    QString category;
    int timeout = -1;
    qint64 time = 0;
    bool transient = false;
    bool resident = false;
    bool popup = false;
    bool expired = false;
    bool inlineReply = false;
    QString replyPlaceholder;
    QString replySubmitText;
    QString originName;
    QStringList urls;
    QString soundName;
    QString soundFile;
    bool suppressSound = false;

    bool operator==(const NotificationData &) const = default;
    bool hasAction(const QString &key) const;
};

struct InhibitorData {
    QString desktopEntry;
    QString appName;
    QString reason;

    bool operator==(const InhibitorData &) const = default;
};

struct DoNotDisturbData {
    bool enabled = false;
    qint64 until = 0;
    QList<InhibitorData> inhibitors;
    bool active = false;

    bool operator==(const DoNotDisturbData &) const = default;
};

} // namespace MaiaNotifications
