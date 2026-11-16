#pragma once

// The values of the notification service as plain Qt values, without Cap'n Proto: what the models
// and the connections keep. Contract.h translates them from and to the contract.
//
// The numbers of urgency and close reasons are the contract's: Normal 0, Low 1, Critical 2;
// Expired 0, Dismissed 1, ClosedByApp 2, Other 3.

#include "NotificationFiles.h"

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
    // Files or places it is about (a screenshot): URLs or absolute paths
    QStringList urls;
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
    // The urls as a shell shows them, read with the notification (NotificationFiles.h)
    QList<FileData> files;
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

// A job (the progress of a copy, an archive); state: Running 0, Suspended 1, Finished 2, Failed 3
struct JobFieldData {
    QString label;
    QString value;

    bool operator==(const JobFieldData &) const = default;
};

struct JobData {
    quint32 id = 0;
    QString appName;
    QString desktopEntry;
    QString appIcon;
    QString title;
    QString infoMessage;
    int state = 0;
    int percent = -1;
    quint64 processedBytes = 0;
    quint64 totalBytes = 0;
    quint64 processedFiles = 0;
    quint64 totalFiles = 0;
    quint64 processedDirectories = 0;
    quint64 totalDirectories = 0;
    quint64 processedItems = 0;
    quint64 totalItems = 0;
    quint64 speed = 0;
    qint64 elapsed = 0;
    QList<JobFieldData> fields;
    QString destination;
    quint32 errorCode = 0;
    QString errorText;
    bool ownerGone = false;
    bool killable = false;
    bool suspendable = false;
    qint64 started = 0;
    qint64 updated = 0;

    bool operator==(const JobData &) const = default;
    bool running() const { return state == 0 || state == 1; }
};

// What a shell does itself, by the user's settings
struct ShellSettingsData {
    bool lockScreenNotifications = true;

    bool operator==(const ShellSettingsData &) const = default;
};

// An application that sends notifications, and whether the user lets it (NotificationSettings)
struct AppNotificationsData {
    QString key;
    QString desktopEntry;
    QString appName;
    QString appIcon;
    bool enabled = true;
    bool sent = false;
    bool declared = false;

    bool operator==(const AppNotificationsData &) const = default;
};

struct SettingsData {
    DoNotDisturbData doNotDisturb;
    ShellSettingsData shell;
    QList<AppNotificationsData> apps;
};

// What a program says about its job (Notifier.startJob, JobHandle.update): its whole state
struct JobProgressData {
    QString title;
    QString infoMessage;
    int percent = -1;
    quint64 processedBytes = 0;
    quint64 totalBytes = 0;
    quint64 processedFiles = 0;
    quint64 totalFiles = 0;
    quint64 processedDirectories = 0;
    quint64 totalDirectories = 0;
    quint64 processedItems = 0;
    quint64 totalItems = 0;
    quint64 speed = 0;
    QList<JobFieldData> fields;
    QString destination;
    bool suspended = false;
};

struct JobRequestData {
    QString appName;
    QString desktopEntry;
    QString appIcon;
    bool killable = false;
    bool suspendable = false;
    bool immediate = false;
    bool transient = false;
    JobProgressData progress;
};

} // namespace MaiaNotifications
