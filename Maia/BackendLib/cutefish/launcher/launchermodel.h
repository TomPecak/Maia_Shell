#ifndef LAUNCHERMODEL_H
#define LAUNCHERMODEL_H

#include <qqml.h>
#include <QObject>
#include <QFileSystemWatcher>
#include <QList>
#include <QAbstractListModel>
#include <QTimer>
#include <QSettings>

#include "appitem.h"


class LauncherModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
public:
    enum Roles {
        AppIdRole = Qt::UserRole + 1,
        ApplicationRole,
        NameRole,
        GenericNameRole,
        CommentRole,
        IconNameRole,
        CategoriesRole,
        FilterInfoRole,
        PinnedRole,
        PinnedIndexRole,
        NewInstalledRole
    };
    Q_ENUM(Roles)

    enum Mode {
        NormalMode,
        SearchMode
    };
    Q_ENUM(Mode)

    explicit LauncherModel(QObject *parent = nullptr);
    ~LauncherModel();

    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;

    Q_INVOKABLE void search(const QString &key);
    Q_INVOKABLE void sendToDock(const QString &key);
    Q_INVOKABLE void sendToDesktop(const QString &key);
    Q_INVOKABLE void removeFromDock(const QString &desktop);

    int findById(const QString &id);

    static void refresh(LauncherModel *manager);

    Q_INVOKABLE void move(int from, int to, int page, int pageCount);
    Q_INVOKABLE void save();

    void delaySave();

public slots:
    Q_INVOKABLE bool launch(const QString &path);

Q_SIGNALS:
    void countChanged();
    void refreshed();
        void applicationLaunched();

private slots:
    void onRefreshed();
    void onFileChanged(const QString &path);
    void addApp(const QString &fileName);
    void removeApp(const QString &fileName);


private:
    QList<AppItem> m_appItems;
    QList<AppItem> m_searchItems;

    QFileSystemWatcher *m_fileWatcher;

    QTimer m_saveTimer;
    QSettings m_settings;
    Mode m_mode;

    bool m_firstLoad;
};

#endif // LAUNCHERMODEL_H
