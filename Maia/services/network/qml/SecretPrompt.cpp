#include "SecretPrompt.h"

namespace MaiaNetwork {

namespace {
// The active prompt of the process; another one activated takes over
SecretPrompt *s_active = nullptr;
}

SecretPrompt::SecretPrompt(QObject *parent)
    : QObject(parent)
    , m_source(NetworkSource::instance())
{
    connect(m_source, &NetworkSource::secretRequested, this, [this](const SecretRequestData &request) {
        if (s_active != this)
            return;
        m_queue.append(request);
        if (m_queue.size() == 1)
            Q_EMIT requestChanged();
    });
    connect(m_source, &NetworkSource::secretCancelled, this, [this](const QString &id) {
        for (qsizetype i = 0; i < m_queue.size(); ++i) {
            if (m_queue[i].id != id)
                continue;
            m_queue.removeAt(i);
            if (i == 0) {
                Q_EMIT cancelledByService();
                Q_EMIT requestChanged();
            }
            return;
        }
    });
    // A new connection to the service: the old requests are gone with it
    connect(m_source, &NetworkSource::connectedChanged, this, [this] {
        if (!m_source->isConnected() && !m_queue.isEmpty()) {
            m_queue.clear();
            Q_EMIT requestChanged();
        }
    });
}

SecretPrompt::~SecretPrompt()
{
    setActive(false);
}

void SecretPrompt::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    if (active) {
        if (s_active && s_active != this)
            s_active->setActive(false);
        s_active = this;
        m_source->setPrompterRegistered(true);
    } else {
        // Whatever waits here is cancelled: nobody will answer it
        for (const auto &request : std::as_const(m_queue))
            m_source->answerSecrets(request.id, true, {});
        const bool hadRequest = !m_queue.isEmpty();
        m_queue.clear();
        if (s_active == this) {
            s_active = nullptr;
            m_source->setPrompterRegistered(false);
        }
        if (hadRequest)
            Q_EMIT requestChanged();
    }
    Q_EMIT activeChanged();
}

QString SecretPrompt::name() const
{
    return m_queue.isEmpty() ? QString() : m_queue.first().name;
}

Network::Security SecretPrompt::security() const
{
    return m_queue.isEmpty() ? Network::Security::None : m_queue.first().security;
}

bool SecretPrompt::retry() const
{
    return !m_queue.isEmpty() && m_queue.first().retry;
}

bool SecretPrompt::wpsPushButton() const
{
    return !m_queue.isEmpty() && m_queue.first().wpsPushButton;
}

QVariantList SecretPrompt::fields() const
{
    QVariantList list;
    if (m_queue.isEmpty())
        return list;
    for (const auto &field : m_queue.first().fields) {
        list.append(QVariantMap{
            {QStringLiteral("key"), QVariant::fromValue(field.key)},
            {QStringLiteral("value"), field.value},
            {QStringLiteral("hidden"), field.hidden},
            {QStringLiteral("validation"), QVariant::fromValue(field.validation)},
        });
    }
    return list;
}

bool SecretPrompt::valid(int index, const QString &value) const
{
    if (m_queue.isEmpty() || index < 0 || index >= m_queue.first().fields.size())
        return false;
    return Network::accepts(m_queue.first().fields.at(index).validation, value);
}

void SecretPrompt::answer(const QStringList &values)
{
    if (m_queue.isEmpty())
        return;
    const auto request = m_queue.takeFirst();
    QList<SecretData> secrets;
    for (qsizetype i = 0; i < request.fields.size() && i < values.size(); ++i)
        secrets.append(SecretData{request.fields[i].key, values[i]});
    m_source->answerSecrets(request.id, false, secrets);
    Q_EMIT requestChanged();
}

void SecretPrompt::cancel()
{
    if (m_queue.isEmpty())
        return;
    const auto request = m_queue.takeFirst();
    m_source->answerSecrets(request.id, true, {});
    Q_EMIT requestChanged();
}

} // namespace MaiaNetwork
