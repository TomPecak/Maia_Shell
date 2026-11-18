#pragma once

// CrossProcessState: properties and signals shared by the processes of a session (the layers of a
// shell are separate processes), declared in QML like Settings {}:
//
//   import Maia.CrossProcessState
//
//   CrossProcessState {
//       category: "MaiaShell"                        // same category, same values
//       host: true                                   // in one process only: it keeps the state
//       property bool notificationCenterOpen: false
//       property string dockEdge: "top"
//       signal notificationTapped(int notificationId)
//   }
//
// The declared properties are ordinary QML properties: bindings to them, on…Changed handlers and
// Behaviors work; a change in any process reaches the others at once, as if assigned there. A
// declared signal emitted in one process is emitted in the others too (an event: a process that
// comes later does not get it). Found by reflection (QMetaObject) when the object is complete; the
// properties of CrossProcessState itself are not shared.
//
// Rules, as for Settings {}: the shared properties are values, not bindings (a change from another
// process replaces a binding); objects and lists change as a whole (shell.list = [...], never
// shell.list.push()), or nobody hears it.
//
// host: the process that keeps the state for the others, chosen by the frontend (its longest-living
// process). Participants that start earlier use their declared values (synced: false) and get the
// host's when it comes; when a host comes back, changed values of the participants win over its
// declared defaults. A second host takes part instead (a warning). See Link.h.

#include <QHash>
#include <QObject>
#include <QQmlParserStatus>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <memory>
#include <vector>

namespace MaiaCrossProcessState {

class Link;
class SignalRelay;

class CrossProcessState : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)

    // What is shared: objects of the same category (in any process) share their properties of the
    // same name. Set once, before the object is complete
    Q_PROPERTY(QString category READ category WRITE setCategory NOTIFY categoryChanged)
    // This process keeps the state for the others (set once, before the object is complete)
    Q_PROPERTY(bool host READ host WRITE setHost NOTIFY hostChanged)
    // The values are those of the session (the host has been reached, or this is the host)
    Q_PROPERTY(bool synced READ synced NOTIFY syncedChanged)

public:
    explicit CrossProcessState(QObject *parent = nullptr);
    ~CrossProcessState() override;

    QString category() const { return m_category; }
    void setCategory(const QString &category);
    bool host() const { return m_host; }
    void setHost(bool host);
    bool synced() const { return m_synced; }

    void classBegin() override {}
    void componentComplete() override;

    // The link of this object (the process's own by default; tests may give another before the
    // object is complete)
    void setLink(Link *link) { m_link = link; }

Q_SIGNALS:
    void categoryChanged();
    void hostChanged();
    void syncedChanged();

private:
    friend class Link;
    friend class SignalRelay;

    // From the link: a value or an event of another object or process
    void applyValue(const QString &key, const QVariant &value);
    void applyEvent(const QString &name, const QVariantList &args);
    void setSynced(bool synced);

    // From a relay: one of the watched signals was emitted
    void onSignal(int signalIndex, void **args);

    Link *m_link = nullptr;
    QString m_category;
    bool m_host = false;
    bool m_synced = false;
    bool m_complete = false;
    // While a value or an event from elsewhere is applied: not sent back
    bool m_applying = false;

    // Notify signal → property name; property name → property index; signal → its name
    QHash<int, QString> m_notifySignals;
    QHash<QString, int> m_properties;
    QHash<int, QString> m_signals;
    QHash<QString, int> m_signalIndexes;
    std::vector<std::unique_ptr<SignalRelay>> m_relays;
};

} // namespace MaiaCrossProcessState
