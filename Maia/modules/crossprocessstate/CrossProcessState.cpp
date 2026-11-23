#include "CrossProcessState.h"

#include "Link.h"

#include <QJSValue>
#include <QLoggingCategory>
#include <QMetaMethod>
#include <QQmlEngine>
#include <QMetaProperty>

Q_DECLARE_LOGGING_CATEGORY(lcCrossProcessState)

namespace MaiaCrossProcessState {

// Receives one signal of a CrossProcessState with its arguments, whatever its signature: connected
// to a method index past QObject's own and caught in qt_metacall, as QSignalSpy does
class SignalRelay : public QObject
{
public:
    SignalRelay(CrossProcessState *owner, int signalIndex)
        : m_owner(owner)
        , m_signalIndex(signalIndex)
    {
    }

    bool watch()
    {
        return QMetaObject::connect(m_owner, m_signalIndex, this, QObject::staticMetaObject.methodCount(), Qt::DirectConnection, nullptr);
    }

    int qt_metacall(QMetaObject::Call call, int id, void **args) override
    {
        id = QObject::qt_metacall(call, id, args);
        if (id < 0)
            return id;
        if (call == QMetaObject::InvokeMetaMethod) {
            if (id == 0)
                m_owner->onSignal(m_signalIndex, args);
            --id;
        }
        return id;
    }

private:
    CrossProcessState *m_owner;
    int m_signalIndex;
};

CrossProcessState::CrossProcessState(QObject *parent)
    : QObject(parent)
{
}

CrossProcessState::~CrossProcessState()
{
    m_relays.clear();
    if (m_complete && m_link)
        m_link->detach(this, m_category);
}

void CrossProcessState::setCategory(const QString &category)
{
    if (category == m_category)
        return;
    if (m_complete) {
        qCWarning(lcCrossProcessState) << "the category of a CrossProcessState is set once, before it is complete";
        return;
    }
    m_category = category;
    Q_EMIT categoryChanged();
}

void CrossProcessState::setLink(Link *link)
{
    m_link = link;
}

void CrossProcessState::componentComplete()
{
    m_complete = true;
    if (m_category.isEmpty()) {
        qCWarning(lcCrossProcessState) << "a CrossProcessState without a category shares nothing";
        return;
    }
    if (!m_link)
        m_link = Link::instance();

    // Reflection: what the QML declaration added to this type
    const QMetaObject *meta = metaObject();
    const QMetaObject &own = CrossProcessState::staticMetaObject;
    QVariantHash declared;
    QSet<int> notifySignals;
    for (int i = own.propertyCount(); i < meta->propertyCount(); ++i) {
        const QMetaProperty property = meta->property(i);
        if (!property.isWritable() || !property.hasNotifySignal())
            continue;
        const QString name = QString::fromLatin1(property.name());
        const QVariant value = Link::wireValue(property.read(this));
        if (property.read(this).isValid() && !value.isValid())
            continue; // a type that cannot travel (warned)
        declared.insert(name, value);
        m_properties.insert(name, i);
        m_notifySignals.insert(property.notifySignalIndex(), name);
        notifySignals.insert(property.notifySignalIndex());
    }
    for (int i = own.methodCount(); i < meta->methodCount(); ++i) {
        const QMetaMethod method = meta->method(i);
        if (method.methodType() != QMetaMethod::Signal || notifySignals.contains(i))
            continue;
        const QString name = QString::fromLatin1(method.name());
        m_signals.insert(i, name);
        m_signalIndexes.insert(name, i);
    }
    // Every notify signal and every declared signal, caught with its arguments
    const auto watched = notifySignals.values() + m_signals.keys();
    for (int index : watched) {
        auto relay = std::make_unique<SignalRelay>(this, index);
        if (relay->watch())
            m_relays.push_back(std::move(relay));
    }
    m_link->attach(this, m_category, declared);
}

void CrossProcessState::onSignal(int signalIndex, void **args)
{
    if (m_applying || !m_link)
        return;
    const auto property = m_notifySignals.constFind(signalIndex);
    if (property != m_notifySignals.cend()) {
        const QMetaProperty meta = metaObject()->property(m_properties.value(*property));
        const QVariant value = Link::wireValue(meta.read(this));
        m_link->changedLocally(this, m_category, *property, value);
        return;
    }
    const auto name = m_signals.constFind(signalIndex);
    if (name == m_signals.cend())
        return;
    const QMetaMethod method = metaObject()->method(signalIndex);
    QVariantList values;
    values.reserve(method.parameterCount());
    for (int i = 0; i < method.parameterCount(); ++i) {
        const QMetaType type = method.parameterMetaType(i);
        // A "var" parameter is a QVariant itself: its value, not a variant of a variant
        const QVariant value = type == QMetaType::fromType<QVariant>() ? *static_cast<const QVariant *>(args[i + 1])
                                                                       : QVariant(type, args[i + 1]);
        values.append(Link::wireValue(value));
    }
    m_link->emittedLocally(this, m_category, *name, values);
}

void CrossProcessState::applyValue(const QString &key, const QVariant &value)
{
    const auto index = m_properties.constFind(key);
    if (index == m_properties.cend())
        return; // a key this object does not declare
    const QMetaProperty property = metaObject()->property(*index);
    if (Link::wireValue(property.read(this)) == value)
        return;
    m_applying = true;
    if (!property.write(this, value))
        qCWarning(lcCrossProcessState) << "cannot write" << value << "to" << key;
    m_applying = false;
}

void CrossProcessState::applyEvent(const QString &name, const QVariantList &args)
{
    const auto index = m_signalIndexes.constFind(name);
    if (index == m_signalIndexes.cend())
        return;
    const QMetaMethod method = metaObject()->method(*index);
    const int count = method.parameterCount();
    if (count > 10 || args.size() != count) {
        qCWarning(lcCrossProcessState) << "the signal" << name << "came with" << args.size() << "arguments instead of" << count;
        return;
    }
    // Each argument as the signal's parameter type, alive until the signal is emitted
    QVariantList converted = args;
    QGenericArgument arguments[10];
    for (int i = 0; i < count; ++i) {
        const QMetaType type = method.parameterMetaType(i);
        // A "var" parameter that is a JavaScript value: made by the engine from the map or list
        if (type == QMetaType::fromType<QJSValue>()) {
            QQmlEngine *engine = qmlEngine(this);
            if (!engine) {
                qCWarning(lcCrossProcessState) << "the signal" << name << "needs a QML engine";
                return;
            }
            converted[i] = QVariant::fromValue(engine->toScriptValue(converted[i]));
        } else if (type != QMetaType::fromType<QVariant>() && converted[i].metaType() != type && !converted[i].convert(type)) {
            qCWarning(lcCrossProcessState) << "the signal" << name << "cannot take" << args[i];
            return;
        }
        arguments[i] = type == QMetaType::fromType<QVariant>() ? QGenericArgument("QVariant", &converted[i])
                                                                : QGenericArgument(type.name(), converted[i].constData());
    }
    m_applying = true;
    method.invoke(this, Qt::DirectConnection, arguments[0], arguments[1], arguments[2], arguments[3], arguments[4],
                  arguments[5], arguments[6], arguments[7], arguments[8], arguments[9]);
    m_applying = false;
}

void CrossProcessState::setSynced(bool synced)
{
    if (synced == m_synced)
        return;
    m_synced = synced;
    Q_EMIT syncedChanged();
}

} // namespace MaiaCrossProcessState
