#pragma once

#include <QMetaType>
#include <QString>
#include <QVector>

class QDBusArgument;

struct FavApplication
{
    QString id;
    QString name;
    QString exec;
    QString icon;

    static void registerDBusTypes();
};

Q_DECLARE_METATYPE(FavApplication)
Q_DECLARE_METATYPE(QVector<FavApplication>)

// Marshall the FavApplication data into a D-Bus argument
QDBusArgument &operator<<(QDBusArgument &argument, const FavApplication &favApplication);

// Retrieve the FavApplication data from the D-Bus argument
const QDBusArgument &operator>>(const QDBusArgument &argument, FavApplication &favApplication);
