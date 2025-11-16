#ifndef APPITEM_H
#define APPITEM_H

#include <QString>
#include <QStringList>
#include <QMetaType>
#include <QDebugStateSaver>

class AppItem
{
public:
    AppItem();
    AppItem(const AppItem &info);
    ~AppItem();

    inline bool operator==(const AppItem &other) const { return id == other.id; }
    friend QDataStream &operator<<(QDataStream &argument, const AppItem &info);
    friend const QDataStream &operator>>(QDataStream &argument, AppItem &info);

    QString id;
    QString name;
    QString genericName;
    QString comment;
    QString iconName;
    QStringList args;

    bool newInstalled;
};

inline QDebug operator<<(QDebug debug, const AppItem &info)
{
    QDebugStateSaver saver(debug);
    debug.nospace() << "AppItem(id=" << info.id
                    << ", name=" << info.name
                    << ", genericName=" << info.genericName
                    << ", comment=" << info.comment
                    << ", iconName=" << info.iconName
                    << ", args=" << info.args
                    << ", newInstalled=" << info.newInstalled << ")";
    return debug;
}

Q_DECLARE_METATYPE(AppItem)

#endif // APPITEM_H
