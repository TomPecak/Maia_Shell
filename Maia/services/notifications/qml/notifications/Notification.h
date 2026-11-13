#pragma once

// Notification: one notification of a program, declaratively.
//
//   import Maia.Notifications
//
//   Notification {
//       id: done
//       summary: qsTr("Backup finished")
//       body: qsTr("<b>%1</b> files copied").arg(count)
//       iconName: "drive-harddisk"
//       actions: [{ key: "default", label: "" }, { key: "open", label: qsTr("Open folder") }]
//       onActionInvoked: key => { if (key === "open") openFolder(); done.activate(window) }
//   }
//   … done.send()
//
// send() shows it, or replaces its content while it is shown (a progress, a counter); close()
// takes it away. The service answers at once and keeps it for the session; when this object is
// destroyed the notification stays. Program name and desktop entry default to the application's.
// Without the service (the session is starting) it waits and goes out when the service comes.
//
// The body may use <b>, <i>, <u>, <a href> and <br/>; everything else is shown as text.

#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <QWindow>

namespace MaiaNotifications {

struct RequestData;

class Notification : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString appName READ appName WRITE setAppName NOTIFY changed)
    Q_PROPERTY(QString desktopEntry READ desktopEntry WRITE setDesktopEntry NOTIFY changed)
    // A theme icon name or a file URL
    Q_PROPERTY(QString iconName READ iconName WRITE setIconName NOTIFY changed)
    Q_PROPERTY(QString summary READ summary WRITE setSummary NOTIFY changed)
    Q_PROPERTY(QString body READ body WRITE setBody NOTIFY changed)
    // A picture (a photo, a cover): a local file
    Q_PROPERTY(QUrl image READ image WRITE setImage NOTIFY changed)
    // [{ key, label }]; key "default" is a click on the notification itself
    Q_PROPERTY(QVariantList actions READ actions WRITE setActions NOTIFY changed)
    Q_PROPERTY(Urgency urgency READ urgency WRITE setUrgency NOTIFY changed)
    // "email.arrived", "im.received", "transfer.complete", … (the specification's categories)
    Q_PROPERTY(QString category READ category WRITE setCategory NOTIFY changed)
    // ms of its popup: -1 the shell decides, 0 until the user closes it
    Q_PROPERTY(int timeout READ timeout WRITE setTimeout NOTIFY changed)
    // Gone after its popup (not kept in the list)
    Q_PROPERTY(bool transient READ isTransient WRITE setTransient NOTIFY changed)
    // Stays after one of its actions
    Q_PROPERTY(bool resident READ isResident WRITE setResident NOTIFY changed)
    // A text field; its text comes with replied()
    Q_PROPERTY(bool inlineReply READ inlineReply WRITE setInlineReply NOTIFY changed)
    Q_PROPERTY(QString replyPlaceholder READ replyPlaceholder WRITE setReplyPlaceholder NOTIFY changed)
    Q_PROPERTY(QString replySubmitText READ replySubmitText WRITE setReplySubmitText NOTIFY changed)
    Q_PROPERTY(QString soundName READ soundName WRITE setSoundName NOTIFY changed)
    Q_PROPERTY(bool suppressSound READ suppressSound WRITE setSuppressSound NOTIFY changed)

    // Shown now (sent and not closed)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    // The service's id while shown, 0 otherwise
    Q_PROPERTY(uint notificationId READ notificationId NOTIFY notificationIdChanged)

public:
    // The numbers are those of the contract (notifications.capnp)
    enum Urgency { Normal, Low, Critical };
    Q_ENUM(Urgency)
    enum CloseReason { Expired, Dismissed, ClosedByApp, Other };
    Q_ENUM(CloseReason)

    explicit Notification(QObject *parent = nullptr);
    ~Notification() override;

    Q_INVOKABLE void send();
    Q_INVOKABLE void close();
    // Raises `window` with the activation token of the last action or reply (Wayland lets only a
    // window the user asked for come forward); does nothing without one
    Q_INVOKABLE void activate(QWindow *window);

    QString appName() const { return m_appName; }
    void setAppName(const QString &value);
    QString desktopEntry() const { return m_desktopEntry; }
    void setDesktopEntry(const QString &value);
    QString iconName() const { return m_iconName; }
    void setIconName(const QString &value);
    QString summary() const { return m_summary; }
    void setSummary(const QString &value);
    QString body() const { return m_body; }
    void setBody(const QString &value);
    QUrl image() const { return m_image; }
    void setImage(const QUrl &value);
    QVariantList actions() const { return m_actions; }
    void setActions(const QVariantList &value);
    Urgency urgency() const { return m_urgency; }
    void setUrgency(Urgency value);
    QString category() const { return m_category; }
    void setCategory(const QString &value);
    int timeout() const { return m_timeout; }
    void setTimeout(int value);
    bool isTransient() const { return m_transient; }
    void setTransient(bool value);
    bool isResident() const { return m_resident; }
    void setResident(bool value);
    bool inlineReply() const { return m_inlineReply; }
    void setInlineReply(bool value);
    QString replyPlaceholder() const { return m_replyPlaceholder; }
    void setReplyPlaceholder(const QString &value);
    QString replySubmitText() const { return m_replySubmitText; }
    void setReplySubmitText(const QString &value);
    QString soundName() const { return m_soundName; }
    void setSoundName(const QString &value);
    bool suppressSound() const { return m_suppressSound; }
    void setSuppressSound(bool value);

    bool isActive() const { return m_local != 0; }
    uint notificationId() const { return m_id; }

Q_SIGNALS:
    void changed();
    void activeChanged();
    void notificationIdChanged();
    void actionInvoked(const QString &key);
    void replied(const QString &text);
    void closed(MaiaNotifications::Notification::CloseReason reason);

private:
    friend class NotifierConnection;
    // From the connection, for this object's notification only
    void onSent(uint id);
    void onActionInvoked(const QString &key, const QString &token);
    void onReplied(const QString &text, const QString &token);
    void onClosed(int reason);

    RequestData request() const;
    void setLocal(int local);

    QString m_appName;
    QString m_desktopEntry;
    QString m_iconName;
    QString m_summary;
    QString m_body;
    QUrl m_image;
    QVariantList m_actions;
    Urgency m_urgency = Normal;
    QString m_category;
    int m_timeout = -1;
    bool m_transient = false;
    bool m_resident = false;
    bool m_inlineReply = false;
    QString m_replyPlaceholder;
    QString m_replySubmitText;
    QString m_soundName;
    bool m_suppressSound = false;

    int m_local = 0;
    uint m_id = 0;
    QString m_activationToken;
};

} // namespace MaiaNotifications
