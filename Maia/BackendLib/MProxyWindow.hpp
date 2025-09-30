#pragma once

#include <QProcess>
#include <QQuickItem>
#include <QQuickWindow>
#include <QUrl>

#include "./client/private/ProxyWindowController.hpp"

class MProxyWindow : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(int swapInterval READ swapInterval WRITE setSwapInterval NOTIFY swapIntervalChanged)
    Q_PROPERTY(bool proxyVisible READ proxyVisible WRITE setProxyVisible NOTIFY proxyVisibleChanged)

public:
    explicit MProxyWindow(QQuickItem *parent = nullptr);
    ~MProxyWindow();

    //source
    QUrl source() const { return m_sourceUrl; }
    void setSource(const QUrl &source);

    //proxyVisible
    bool proxyVisible() const;
    void setProxyVisible(bool visible);

    //swap interwal
    int swapInterval() const;
    void setSwapInterval(const int swapInterval);

signals:
    void sourceChanged();
    void swapIntervalChanged();
    void proxyVisibleChanged();

private slots:
    void onWindowChanged(QQuickWindow *window);
    void onAfterSynchronizing();
    void onProcessStarted();
    void onProcessReadyReadStandardOutput();
    void onProcessReadyReadStandardError();
    void handleVisibleReceived(bool visible);
    void handleProxyWindowConnected();

private:
    void startProcess();
    void stopProcess();

    QProcess *m_process;
    QUrl m_sourceUrl;
    ProxyWindowController *m_winController;
    QString m_serverName;

    int m_swapInterval;
    bool m_proxyWindowVisible = false;
};
