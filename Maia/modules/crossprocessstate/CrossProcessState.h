#pragma once

// CrossProcessState: properties and signals shared by the processes of a session (the layers of a
// shell are separate processes). Declare them once, use them anywhere:
//
//   // ShellState.qml (in the qmldir: singleton ShellState 1.0 ShellState.qml)
//   pragma Singleton
//   import Maia.CrossProcessState
//
//   CrossProcessState {
//       category: "MaiaShell"                        // same category, same values
//       property bool notificationCenterOpen: false
//       property bool controlCenterOpen: false
//       readonly property bool anyOpen: notificationCenterOpen || controlCenterOpen   // derived
//       signal notificationTapped(int notificationId)
//   }
//
//   // In any file of any process
//   Sheet { open: ShellState.notificationCenterOpen }
//   Button { onClicked: ShellState.notificationCenterOpen = true }
//
// That is all: no server to start, no roles. The first process hosts the state, another one takes
// over when it is gone (Link.h).
//
// The declared properties are ordinary QML properties: bindings to them, on…Changed handlers and
// Behaviors work; a change in any process reaches the others at once, as if assigned there. A
// declared signal emitted in one process is emitted in the others too (an event: a process that
// comes later does not get it). Found by reflection (QMetaObject) when the object is complete. A
// readonly property is not shared: it is derived, in each process, from the shared ones.
//
// Rules: a shared property holds a value, not a binding (a change from another process replaces a
// binding; for a derived value use readonly); objects and lists change as a whole
// (state.list = [...], never state.list.push()), or nobody hears it.

#include <QHash>
#include <QObject>
#include <QPointer>
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
    // The values are those of the session. False only for a moment: at the start of a process that
    // is not the first, and while another process takes over from a host that is gone
    Q_PROPERTY(bool synced READ synced NOTIFY syncedChanged)

public:
    explicit CrossProcessState(QObject *parent = nullptr);
    ~CrossProcessState() override;

    QString category() const { return m_category; }
    void setCategory(const QString &category);
    bool synced() const { return m_synced; }

    void classBegin() override {}
    void componentComplete() override;

    // The link of this object (the process's own by default; tests may give another before the
    // object is complete)
    void setLink(Link *link);

Q_SIGNALS:
    void categoryChanged();
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

    QPointer<Link> m_link;
    QString m_category;
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
