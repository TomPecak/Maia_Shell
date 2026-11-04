#pragma once

// Password requests of NetworkManager, for the shell's password dialog (docs/gnome-wifi-features.md,
// section 5). The shell creates one, active while it can show dialogs; the network service then
// sends it the requests of the secret agent:
//
//   SecretPrompt {
//       id: prompt
//       active: true
//       onPendingChanged: dialog.visible = pending
//   }
//   // the dialog shows prompt.name, a field per prompt.fields[i] (key, value, hidden, validation),
//   // "Wrong password?" when prompt.retry, and enables Connect when every field passes
//   // Network.accepts / prompt.valid(i, text)
//   Button { text: qsTr("Connect"); onClicked: prompt.answer(values) }   // values: one string per field
//   Button { text: qsTr("Cancel"); onClicked: prompt.cancel() }
//
// Only one prompter is registered per session; a new active SecretPrompt (e.g. after switching
// frontends) takes over. Requests wait in order; the first is the pending one.

#include "NetworkSource.h"

#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace MaiaNetwork {

class SecretPrompt : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    // A request waits for an answer
    Q_PROPERTY(bool pending READ pending NOTIFY requestChanged)
    Q_PROPERTY(QString name READ name NOTIFY requestChanged)
    Q_PROPERTY(MaiaNetwork::Network::Security security READ security NOTIFY requestChanged)
    // The saved password was refused: ask again ("Wrong password?")
    Q_PROPERTY(bool retry READ retry NOTIFY requestChanged)
    // The router offers WPS push button
    Q_PROPERTY(bool wpsPushButton READ wpsPushButton NOTIFY requestChanged)
    // [{ key: Network.SecretKey, value: prefilled text, hidden: bool, validation: Network.Validation }]
    Q_PROPERTY(QVariantList fields READ fields NOTIFY requestChanged)

public:
    explicit SecretPrompt(QObject *parent = nullptr);
    ~SecretPrompt() override;

    bool active() const { return m_active; }
    void setActive(bool active);
    bool pending() const { return !m_queue.isEmpty(); }
    QString name() const;
    Network::Security security() const;
    bool retry() const;
    bool wpsPushButton() const;
    QVariantList fields() const;

    // Whether `value` passes the check of field `index`
    Q_INVOKABLE bool valid(int index, const QString &value) const;
    // Answers the pending request with one value per field, in the order of `fields`
    Q_INVOKABLE void answer(const QStringList &values);
    Q_INVOKABLE void cancel();

Q_SIGNALS:
    void activeChanged();
    void requestChanged();
    // The service no longer needs the pending answer (e.g. the connection was cancelled elsewhere)
    void cancelledByService();

private:
    void next();

    NetworkSource *m_source;
    bool m_active = false;
    QList<SecretRequestData> m_queue;
};

} // namespace MaiaNetwork
