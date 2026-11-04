#pragma once

// Small pieces shared by the QML types of Maia.Network.

#include "NetworkSource.h"

#include <QAbstractListModel>
#include <QJSEngine>
#include <QJSValue>
#include <QPointer>
#include <QStringList>

namespace MaiaNetwork {

// A JavaScript callback for a command: called with { ok, error, message } (error: Network.ErrorCode)
inline NetworkSource::Callback jsCallback(QObject *owner, const QJSValue &callback)
{
    if (!callback.isCallable())
        return {};
    return [owner = QPointer<QObject>(owner), callback](const Result &result) mutable {
        QJSEngine *engine = owner ? qjsEngine(owner) : nullptr;
        if (!engine)
            return;
        QJSValue object = engine->newObject();
        object.setProperty(QStringLiteral("ok"), result.error == Network::ErrorCode::None);
        object.setProperty(QStringLiteral("error"), int(result.error));
        object.setProperty(QStringLiteral("message"), result.message);
        callback.call({object});
    };
}

// A list model of ids in an order of its own: sync() turns the rows into a new order with the least
// row changes (removes, inserts, moves), so delegates stay and can animate.
class SortedIdModel : public QAbstractListModel
{
    Q_OBJECT

public:
    using QAbstractListModel::QAbstractListModel;

    int rowCount(const QModelIndex &parent = {}) const override { return parent.isValid() ? 0 : int(m_ids.size()); }

protected:
    const QStringList &ids() const { return m_ids; }

    void sync(const QStringList &target)
    {
        for (qsizetype i = m_ids.size() - 1; i >= 0; --i) {
            if (!target.contains(m_ids[i])) {
                beginRemoveRows({}, int(i), int(i));
                m_ids.removeAt(i);
                endRemoveRows();
            }
        }
        for (qsizetype i = 0; i < target.size(); ++i) {
            const qsizetype current = m_ids.indexOf(target[i]);
            if (current < 0) {
                beginInsertRows({}, int(i), int(i));
                m_ids.insert(i, target[i]);
                endInsertRows();
            } else if (current != i) {
                // Rows before i are final, so current > i
                beginMoveRows({}, int(current), int(current), {}, int(i));
                m_ids.move(current, i);
                endMoveRows();
            }
        }
        if (m_count != m_ids.size()) {
            m_count = m_ids.size();
            Q_EMIT countChanged();
        }
    }

    void rowChanged(const QString &id)
    {
        const qsizetype row = m_ids.indexOf(id);
        if (row >= 0)
            Q_EMIT dataChanged(index(int(row)), index(int(row)));
    }

Q_SIGNALS:
    void countChanged();

private:
    QStringList m_ids;
    qsizetype m_count = 0;
};

} // namespace MaiaNetwork
