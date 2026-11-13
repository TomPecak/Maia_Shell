#pragma once

// NotificationPopupsModel: the notifications to show as popups now, the oldest first: data and
// behaviour, no look. The shell draws them as it likes (Lumen: cards in the bottom-right corner, a
// tablet face: one banner at the top) and only sets how many, how long and when to pause.
//
// The service decides which notifications pop up at all (popup: not during do not
// disturb, not low urgency); this model decides for how long, which is the shell's to count:
//
// - at most maximumCount at once; the rest waits and comes when one goes, critical ones first;
// - each stays for its timeout: the sender's, or defaultTimeout when the sender leaves it to the
//   shell; 0, and critical ones without a timeout, stay until closed;
// - paused (the pointer is over the popups) stops every clock; they go on where they stopped;
// - when its time is over a popup goes and the service is told (expire): the notification stays
//   in the list of NotificationsModel. hide() does the same at once (the popup was swiped away);
// - suppressed (the user works fullscreen: Maia.Windows' FullscreenState) shows only critical
//   popups: the others go into the list at once, those on screen go too, and nothing comes back
//   when it ends.
//
// - popupShown tells when a new popup appears, with what the sender asked to hear (a name of the
//   sound theme or a file): the shell plays it (Maia.Sounds). Not for the popups found after a
//   (re)connection, not when a shown popup gets new content.
//
// One process of a shell shows popups: two models in a session would show every popup twice.
//
// One timer for all popups (the nearest end). Roles: those of NotificationsModel (NotificationRoles.h).
//
//   Repeater { model: NotificationPopupsModel { paused: hover.hovered } delegate: Popup { … } }

#include "NotificationData.h"

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QSet>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

namespace MaiaNotifications {

class NotificationPopupsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int maximumCount READ maximumCount WRITE setMaximumCount NOTIFY maximumCountChanged)
    // ms of a popup whose sender leaves the time to the shell
    Q_PROPERTY(int defaultTimeout READ defaultTimeout WRITE setDefaultTimeout NOTIFY defaultTimeoutChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    // Only critical popups (fullscreen); the others go into the list without a popup
    Q_PROPERTY(bool suppressed READ suppressed WRITE setSuppressed NOTIFY suppressedChanged)
    // How many wait for a free place
    Q_PROPERTY(int waiting READ waiting NOTIFY waitingChanged)

public:
    explicit NotificationPopupsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int maximumCount() const { return m_maximumCount; }
    void setMaximumCount(int count);
    int defaultTimeout() const { return m_defaultTimeout; }
    void setDefaultTimeout(int ms);
    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    bool suppressed() const { return m_suppressed; }
    void setSuppressed(bool suppressed);
    int waiting() const { return int(m_waiting.size()); }

    // The popup goes now (swiped away); the notification stays in the list
    Q_INVOKABLE void hide(uint notificationId);

    // The shortest time a popup is shown, whatever its sender asks
    static constexpr int kMinimumTimeout = 1000;

Q_SIGNALS:
    void countChanged();
    void maximumCountChanged();
    void defaultTimeoutChanged();
    void pausedChanged();
    void suppressedChanged();
    // A new popup is on screen. soundName: of the sound theme; soundFile: a file URL; suppressSound:
    // the sender plays its own (or wants none)
    void popupShown(uint notificationId, const QString &soundName, const QString &soundFile, bool suppressSound);
    void waitingChanged();

private:
    struct Popup {
        NotificationData data;
        // ms left; < 0 = stays until closed
        qint64 remaining = -1;
        // Since the clock last ran on
        QElapsedTimer running;
    };

    void reload();
    // Into the queue: critical ones before the others
    void enqueue(const NotificationData &n);
    void applyBatch(const QList<NotificationData> &changed, const QList<quint32> &removed);
    bool wantsPopup(const NotificationData &n) const;
    // Suppressed and not critical: into the list without a popup
    bool keptQuiet(const NotificationData &n) const;
    qint64 timeoutOf(const NotificationData &n) const;
    int rowOf(quint32 id) const;
    void removeRow(int row);
    void fill();
    void show(const NotificationData &n);
    void restartTimer();
    void timeUp();
    qint64 leftOf(const Popup &popup) const;

    QList<Popup> m_popups;
    QList<quint32> m_waiting;
    QTimer m_timer;
    int m_maximumCount = 3;
    int m_defaultTimeout = 6000;
    bool m_paused = false;
    bool m_suppressed = false;
    // Popups already announced (popupShown), until they leave for good
    QSet<quint32> m_announced;
};

} // namespace MaiaNotifications
