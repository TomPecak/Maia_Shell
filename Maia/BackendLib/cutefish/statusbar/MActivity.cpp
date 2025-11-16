#include "MActivity.hpp"

#include <QFile>
#include <QCursor>
#include <QDebug>
#include <QDirIterator>
#include <QSettings>
#include <QRegularExpression>

#include <KX11Extras>
#include <KWindowSystem>
#include <KWindowInfo>

#include <NETWM>


static const QStringList blockList = {"cutefish-launcher",
                                      "cutefish-statusbar"};

MActivity::MActivity(QObject *parent)
    : QObject(parent)
    , m_cApps(CApplications::self())
{
    onActiveWindowChanged();

    connect(KX11Extras::self(), &KX11Extras::activeWindowChanged, this, &MActivity::onActiveWindowChanged);
    connect(KX11Extras::self(), static_cast<void (KX11Extras::*)(WId id, NET::Properties properties, NET::Properties2 properties2)>(&KX11Extras::windowChanged),
            this, &MActivity::onActiveWindowChanged);
}

bool MActivity::launchPad() const
{
    return m_launchPad;
}

QString MActivity::title() const
{
    return m_title;
}

QString MActivity::icon() const
{
    return m_icon;
}

void MActivity::close()
{
    NETRootInfo(x11Connection(), NET::CloseWindow).closeWindowRequest(KX11Extras::activeWindow());
}

void MActivity::minimize()
{
    KX11Extras::minimizeWindow(KX11Extras::activeWindow());
}

void MActivity::restore()
{
    KX11Extras::clearState(KX11Extras::activeWindow(), NET::Max);
}

void MActivity::maximize()
{
    KX11Extras::setState(KX11Extras::activeWindow(), NET::Max);
}

void MActivity::toggleMaximize()
{
    KWindowInfo info(KX11Extras::activeWindow(), NET::WMState);
    bool isWindow = !info.hasState(NET::SkipTaskbar) ||
                    info.windowType(NET::UtilityMask) != NET::Utility ||
                    info.windowType(NET::DesktopMask) != NET::Desktop;

    if (!isWindow)
        return;

    bool isMaximized = info.hasState(NET::Max);
    isMaximized ? restore() : maximize();
}

void MActivity::move()
{
    WId winId = KX11Extras::activeWindow();
    KWindowInfo info(winId, NET::WMState | NET::WMGeometry | NET::WMDesktop);
    bool window = !info.hasState(NET::SkipTaskbar) ||
                  info.windowType(NET::UtilityMask) != NET::Utility ||
                  info.windowType(NET::DesktopMask) != NET::Desktop;

    if (!window)
        return;

    bool onCurrent = info.isOnCurrentDesktop();
    if (!onCurrent) {
        KX11Extras::setCurrentDesktop(info.desktop());
        KX11Extras::forceActiveWindow(winId);
    }

    NETRootInfo ri(x11Connection(), NET::WMMoveResize);
    ri.moveResizeRequest(winId,
                         QCursor::pos().x(),
                         QCursor::pos().y(), NET::Move);
}

bool MActivity::isAcceptableWindow(quint64 wid)
{
    QFlags<NET::WindowTypeMask> ignoreList;
    ignoreList |= NET::DesktopMask;
    ignoreList |= NET::DockMask;
    ignoreList |= NET::SplashMask;
    ignoreList |= NET::ToolbarMask;
    ignoreList |= NET::MenuMask;
    ignoreList |= NET::PopupMenuMask;
    ignoreList |= NET::NotificationMask;

    KWindowInfo info(wid, NET::WMWindowType | NET::WMState, NET::WM2TransientFor | NET::WM2WindowClass);

    if (!info.valid())
        return false;

    if (NET::typeMatchesMask(info.windowType(NET::AllTypesMask), ignoreList))
        return false;

    if (info.hasState(NET::SkipTaskbar) || info.hasState(NET::SkipPager))
        return false;

    // WM_TRANSIENT_FOR hint not set - normal window
    WId transFor = info.transientFor();
    if (transFor == 0 || transFor == wid || transFor == (WId) rootWindow())
        return true;

    info = KWindowInfo(transFor, NET::WMWindowType);

    QFlags<NET::WindowTypeMask> normalFlag;
    normalFlag |= NET::NormalMask;
    normalFlag |= NET::DialogMask;
    normalFlag |= NET::UtilityMask;

    return !NET::typeMatchesMask(info.windowType(NET::AllTypesMask), normalFlag);
}

void MActivity::onActiveWindowChanged()
{
    KWindowInfo info(KX11Extras::activeWindow(),
                     NET::WMState | NET::WMVisibleName | NET::WMWindowType,
                     NET::WM2WindowClass);

#warning 'this should be removed'
    m_launchPad = (info.windowClassClass() == "cutefish-launcher");
    emit launchPadChanged();

    if (NET::typeMatchesMask(info.windowType(NET::AllTypesMask), NET::DesktopMask)) {
        m_title = tr("Desktop");
        m_icon = "";

        emit titleChanged();
        emit iconChanged();

        return;
    }

    if (!isAcceptableWindow(KX11Extras::activeWindow())
        || blockList.contains(info.windowClassClass())) {
        clearTitle();
        clearIcon();
        return;
    }

    m_pid = info.pid();
    m_windowClass = info.windowClassClass().toLower();

    CAppItem *item = m_cApps->matchItem(m_pid, m_windowClass);

    if (item) {
        m_title = item->localName;
        emit titleChanged();

        if (m_icon != item->icon) {
            m_icon = item->icon;
            emit iconChanged();
        }

    } else {
        QString title = info.visibleName();
        if (title != m_title) {
            m_title = title;
            emit titleChanged();
            clearIcon();
        }
    }
}

void MActivity::clearTitle()
{
    m_title.clear();
    emit titleChanged();
}

void MActivity::clearIcon()
{
    m_icon.clear();
    emit iconChanged();
}

xcb_connection_t * MActivity::x11Connection()
{
    auto *x11App = qApp->nativeInterface<QNativeInterface::QX11Application>();
    return x11App->connection();
}

xcb_window_t MActivity::rootWindow()
{
    return NETRootInfo(x11Connection(),NET::Properties()).rootWindow();
}
