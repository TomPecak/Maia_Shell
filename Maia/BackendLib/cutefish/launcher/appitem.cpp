#include "appitem.h"

AppItem::AppItem()
    : newInstalled(false)
{

}

AppItem::AppItem(const AppItem &info)
    : id(info.id)
    , name(info.name)
    , genericName(info.genericName)
    , comment(info.comment)
    , iconName(info.iconName)
    , args(info.args)
    , newInstalled(false)
{

}

AppItem::~AppItem()
{

}

QDataStream &operator<<(QDataStream &argument, const AppItem &info)
{
    argument << info.id << info.name << info.genericName;
    argument << info.comment << info.iconName;

    return argument;
}

const QDataStream &operator>>(QDataStream &argument, AppItem &info)
{
    argument >> info.id >> info.name >> info.genericName;
    argument >> info.comment >> info.iconName;

    return argument;
}
