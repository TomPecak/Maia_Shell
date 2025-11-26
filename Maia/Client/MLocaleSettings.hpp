#pragma once

#include <qqml.h>
#include <QObject>

class MLocaleSettings: public QObject{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit MLocaleSettings(QObject *parent = nullptr);
    ~MLocaleSettings();

};
