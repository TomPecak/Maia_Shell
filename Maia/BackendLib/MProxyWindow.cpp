#include "MProxyWindow.hpp"
#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTimer>
#include <QUuid>
#include <QVariant>

MProxyWindow::MProxyWindow(QQuickItem *parent)
    : QQuickItem(parent)
    , m_swapInterval(1)
    , m_serverName(QString("/tmp/MProxyWindowServer%1")
                       .arg(QUuid::createUuid().toString(QUuid::WithoutBraces).remove('-')))
{
    setFlag(ItemHasContents, false);
    setVisible(false);

    m_process = new QProcess(this);
    m_winController = new ProxyWindowController(this);

    connect(m_process, &QProcess::started, this, &MProxyWindow::onProcessStarted);
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        qDebug() << "[ERROR] MProxyWindow: Failed to start process. Error:" << error;
    });
    connect(m_process,
            &QProcess::readyReadStandardOutput,
            this,
            &MProxyWindow::onProcessReadyReadStandardOutput);
    connect(m_process,
            &QProcess::readyReadStandardError,
            this,
            &MProxyWindow::onProcessReadyReadStandardError);

    connect(m_winController,
            &ProxyWindowController::visibleReceived,
            this,
            &MProxyWindow::handleVisibleReceived);

    connect(m_winController,
            &ProxyWindowController::proxyWindowConnected,
            this,
            &MProxyWindow::handleProxyWindowConnected);

    connect(this, &QQuickItem::windowChanged, this, &MProxyWindow::onWindowChanged);
}

MProxyWindow::~MProxyWindow()
{
    //qDebug() << __PRETTY_FUNCTION__ << "Process state:" << m_process->state();

    // Clean up the controller
    //qDebug() << "Disconnecting and deleting ProxyWindowController...";
    m_winController->disconnect();
    m_winController->deleteLater();
    m_winController = nullptr;

    m_process->setParent(nullptr);
#warning "//TODO What if the process doesen't close?"
    connect(m_process, &QProcess::finished, m_process, &QObject::deleteLater);
    stopProcess();

    // Remove the Unix socket
    qDebug() << "Removing Unix socket:" << m_serverName;
    QFile::remove(m_serverName);
}

void MProxyWindow::setSource(const QUrl &source)
{
    QUrl finalSource = source;

    if (finalSource.isRelative() && !finalSource.isEmpty()) {
        // Proper use of the static method. We don't need a pointer to the engine.
        QQmlContext *context = QQmlEngine::contextForObject(this);

        if (context) {
            // Use the context to resolve the relative URL.
            finalSource = context->resolvedUrl(source);
        } else {
            // This error may occur if the object was not created by the QML engine
            // (e.g., it was created manually in C++ and is not associated with a context).
            qDebug() << "MProxyWindow: Could not get QML context for object. Cannot resolve "
                          "relative URL:"
                       << source;
        }
    }

    if (m_sourceUrl != finalSource) {
        m_sourceUrl = finalSource;
        emit sourceChanged();
    }
}

bool MProxyWindow::proxyVisible() const
{
    //qDebug() << "[INFO] " << __PRETTY_FUNCTION__;
    return m_proxyWindowVisible;
}

void MProxyWindow::setProxyVisible(bool visible)
{
    if (m_proxyWindowVisible != visible) {
        m_proxyWindowVisible = visible;
        m_winController->setVisible(m_proxyWindowVisible);
        emit proxyVisibleChanged();
    }
}

int MProxyWindow::swapInterval() const
{
    return m_swapInterval;
}

void MProxyWindow::setSwapInterval(const int swapInterval)
{
    if (m_swapInterval != swapInterval) {
        m_swapInterval = swapInterval;
        emit swapIntervalChanged();
    }
}

void MProxyWindow::onWindowChanged(QQuickWindow *window)
{
    if (window) {
        connect(window,
                &QQuickWindow::afterSynchronizing,
                this,
                &MProxyWindow::onAfterSynchronizing,
                Qt::UniqueConnection);
    }
}

void MProxyWindow::onAfterSynchronizing()
{
    startProcess(); //we start windows after synchornization becaouse after synchronization window geomerty is calculated
    disconnect(window(),
               &QQuickWindow::afterSynchronizing,
               this,
               &MProxyWindow::onAfterSynchronizing); // Disconnect to avoid multiple calls
}

void MProxyWindow::startProcess()
{
    if (m_process->state() == QProcess::Running) {
        return;
    }

    if (m_sourceUrl.isEmpty()) {
        return;
    }

    QString program = QCoreApplication::applicationFilePath();

    QStringList args = {"--mode",
                        "client",
                        "--source",
                        m_sourceUrl.toString(),
                        "--proxy-window-addr",
                        m_serverName,
                        "--x",
                        QString::number(x()),
                        "--y",
                        QString::number(y()),
                        "--width",
                        QString::number(width()),
                        "--height",
                        QString::number(height()),
                        "--swap-interval",
                        QString::number(swapInterval()),
                        "--proxy-visible",
                        QVariant(m_proxyWindowVisible).toString()};

    //qDebug() << "444444444444444 " << QVariant(m_proxyWindowVisible).toString();
    //qDebug() << "555555555555555 m_proxyWindowVisible = " << m_proxyWindowVisible;

    m_process->start(program, args);
}

void MProxyWindow::onProcessStarted()
{
    //qDebug() << "[INFO] " << __PRETTY_FUNCTION__ << " Try connect to Proxy Window Server";
    m_winController->connectToServer(m_serverName);
}

void MProxyWindow::onProcessReadyReadStandardOutput()
{
    // Read everything available on standard output
    const QByteArray data = m_process->readAllStandardOutput();
    // Print it to the console of the main process with a prefix to indicate its source
    // Use noquote() to avoid extra quotes and trimmed() to remove trailing whitespace
    //qDebug().noquote() << "[REMOTE STDOUT]" << QString::fromLocal8Bit(data).trimmed();
}

void MProxyWindow::onProcessReadyReadStandardError()
{
    // Read everything available on standard error
    const QByteArray data = m_process->readAllStandardError();
    // Print it as a warning to the console of the main process with an appropriate prefix
    //qDebug().noquote() << "[REMOTE STDERR]" << QString::fromLocal8Bit(data).trimmed();
}

void MProxyWindow::handleVisibleReceived(bool visible)
{
    if (m_proxyWindowVisible != visible) {
        m_proxyWindowVisible = visible;
        emit proxyVisibleChanged();
    }
}

void MProxyWindow::handleProxyWindowConnected()
{
    m_winController->setVisible(m_proxyWindowVisible);
}

void MProxyWindow::stopProcess()
{
    if (m_process->state() != QProcess::NotRunning) {
        m_process->terminate();
    }
}
