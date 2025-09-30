#pragma once

#include <QString>

struct FrontendInfo{
    QString id;
    QString name;
    QString description;

    //load by qml qmlFilePath
    QString qmlFilePath;

    // Load by qml uri and qml type name
    //parameters required by QQmlApplicationEngine::loadFromModule(QAnyStringView uri, QAnyStringView typeName)
    QString qmlUri;
    QString qmlTypeName;
};
