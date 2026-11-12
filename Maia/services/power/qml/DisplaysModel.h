#pragma once

// DisplaysModel: the screens whose brightness Maia can set (today the built-in panel; external
// monitors later), for a settings page.
//
// Roles: id, kind (0 built-in, 1 external), device (the kernel's name), brightness (0 .. 1), minimum.
// setBrightness(id, value) and stepBrightness(id, steps) change one; failures come through
// Power.requestFailed.

#include "PowerConnection.h"

#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

namespace MaiaPower {

class DisplaysModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role { IdRole = Qt::UserRole + 1, KindRole, DeviceRole, BrightnessRole, MinimumRole };
    Q_ENUM(Role)

    explicit DisplaysModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void setBrightness(const QString &id, double brightness);
    Q_INVOKABLE void stepBrightness(const QString &id, int steps);

Q_SIGNALS:
    void countChanged();

private:
    PowerConnection *m_connection;
};

} // namespace MaiaPower
