#pragma once

#include <QString>

struct FrontendInfo{
    QString id;
    QString name;
    QString description;

    // frontend directory: root of its QML module, apps look for their faces in <rootPath>/apps/<app>/
    QString rootPath;

    //load by qml qmlFilePath
    QString qmlFilePath;

    // Load by qml uri and qml type name
    //parameters required by QQmlApplicationEngine::loadFromModule(QAnyStringView uri, QAnyStringView typeName)
    QString qmlUri;
    QString qmlTypeName;
};
