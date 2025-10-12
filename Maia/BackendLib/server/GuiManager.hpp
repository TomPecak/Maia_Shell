#pragma once

#include <QObject>
#include <QProcess>

#include "FrontendInfo.hpp"
#include "QmlGui.hpp"
#include "X11WindowManagerService.hpp"

#include <QScxmlStateMachine>
#include "GuiManagerStateMachine.h"

class GuiManager : public QObject
{
    Q_OBJECT
public:
    explicit GuiManager(QObject *parent = nullptr,
                        QGuiApplication *app = nullptr,
                        int swapIntervalOption = 0);
    ~GuiManager();

    void startGui(const FrontendInfo & frontend);

    void tryLoadFrontend(const FrontendInfo &frontend);

    void uninit();

signals:
    void frontendUnloaded();
    void frontendChanged(const QString frontendId);

private slots:
    void handleKwinReconfigured();

private:
    void loadFrontend();

private:
    QString HOME_ENV;
    WindowManagerX11Service m_x11WindowManagerService;
    QmlGui m_qmlGui;
    QProcess m_kwin;
    FrontendInfo m_currentFrontend;
    GuiManagerStateMachine changeFrontendStateMachine;
};
