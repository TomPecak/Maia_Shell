#pragma once

#include <QAbstractListModel>
#include <QDBusInterface>
#include <qqml.h>

class MFrontendModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString activeFrontend READ activeFrontend WRITE setActiveFrontend NOTIFY activeFrontendChanged)

public:
    explicit MFrontendModel(QObject *parent = nullptr);
    ~MFrontendModel();

    enum FrontendRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        DescriptionRole,
        PathRole,
        ActiveRole
    };

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString activeFrontend() const;
    Q_INVOKABLE void setActiveFrontend(const QString &frontendId);

private slots:
    void handleFrontendListReply(QDBusPendingCallWatcher *watcher);
    void handleFrontendAdded(const QString &id,
                             const QString &name,
                             const QString &description,
                             const QString &path);
    void handleFrontendRemoved(const QString &id);
    void handleActiveFrontendChanged(const QString &frontendId);
    void handleGetActiveFrontend(const QString &frontendId);

signals:
    void activeFrontendChanged();

private:
    struct Frontend {
        QString id;
        QString name;
        QString description;
        QString path;
        bool active;
    };

    QDBusInterface *m_dbusInterface;
    QList<Frontend> m_frontends;
    QString m_activeFrontendIdMirror;

    void loadFrontends();
    void loadActiveFrontend();
};
