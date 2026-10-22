#pragma once

#include <QAbstractListModel>
#include <QVariantMap>
#include <qqml.h>

class FrontendManagerInterface;
class QDBusServiceWatcher;

// List of the installed frontends and the active one, from org.maia.FrontendManager
// (contract: dbus/org.maia.FrontendManager.xml). Works the same in every process: the shell, MProxyWindow
// windows and apps, so it always goes through D-Bus, never calls the service directly.
// All calls are asynchronous: creating the model never blocks the GUI thread.
class MFrontendModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString activeFrontend READ activeFrontend WRITE setActiveFrontend NOTIFY activeFrontendChanged)
    // Directory of the active frontend (root of its QML module); apps find their face in <root>/apps/<app>/
    Q_PROPERTY(QString activeFrontendRootPath READ activeFrontendRootPath NOTIFY activeFrontendChanged)

public:
    explicit MFrontendModel(QObject *parent = nullptr);
    ~MFrontendModel() override;

    enum FrontendRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        DescriptionRole,
        PathRole,
        ActiveRole,
        RootPathRole
    };

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString activeFrontend() const;
    QString activeFrontendRootPath() const;
    Q_INVOKABLE void setActiveFrontend(const QString &frontendId);

Q_SIGNALS:
    void activeFrontendChanged();

private:
    struct Frontend {
        QString id;
        QString name;
        QString description;
        QString path;
        QString rootPath;
        bool active;
    };

    FrontendManagerInterface *m_manager = nullptr;
    QDBusServiceWatcher *m_serviceWatcher = nullptr;
    QList<Frontend> m_frontends;
    QString m_activeFrontendIdMirror;

    void loadState();
    void applyFrontendList(const QList<QVariantMap> &frontends);
    void applyActiveFrontend(const QString &frontendId);
    void addFrontend(const QVariantMap &frontend);
    void removeFrontend(const QString &frontendId);
    static Frontend frontendFromMap(const QVariantMap &map);
};
