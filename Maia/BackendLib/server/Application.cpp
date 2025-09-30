#include "Application.hpp"
#include <QDBusArgument>
#include <QDBusMetaType>

QDBusArgument &operator<<(QDBusArgument &argument, const FavApplication &favApplication)
{
    argument.beginStructure();
    argument << favApplication.id << favApplication.name;
    argument << favApplication.exec << favApplication.icon;
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument, FavApplication &favApplication)
{
    argument.beginStructure();
    argument >> favApplication.id >> favApplication.name;
    argument >> favApplication.exec >> favApplication.icon;
    argument.endStructure();
    return argument;
}

void FavApplication::registerDBusTypes()
{
    qDBusRegisterMetaType<
        FavApplication>(); // register support for (de)marshalling the type FavApplication
    qDBusRegisterMetaType<QVector<FavApplication>>(); // register the return type for getMatches
}
