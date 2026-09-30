#pragma once

#include <QObject>
#include <QProcess>

#include "FrontendInfo.hpp"
#include "QmlGui.hpp"
#include "X11WindowManagerService.hpp"



class GuiManagerStateMachine;

class FrontendLoader : public QObject
{
    Q_OBJECT
public:
    explicit FrontendLoader(QObject *parent = nullptr,
                        QGuiApplication *app = nullptr,
                        int swapIntervalOption = 0);
    ~FrontendLoader();

    void startGui(const FrontendInfo & frontend);

    void tryLoadFrontend(const FrontendInfo &frontend);

    void uninit();

Q_SIGNALS:
    void frontendUnloaded();
    void frontendChanged(const QString frontendId);

private Q_SLOTS:
    void handleKwinReconfigured();

private:
    void loadFrontend();

private:
    QString HOME_ENV;
    WindowManagerX11Service m_x11WindowManagerService;
    QmlGui m_qmlGui;
    QProcess m_kwin;
    FrontendInfo m_currentFrontend;
    GuiManagerStateMachine *changeFrontendStateMachine;
};
