#pragma once

// The look a frontend's shell starts with, declared in its shell/Main.qml:
//
//   import Maia.Appearance
//   FrontendLook { frontend: "XPLuna"; windowDecoration: "aurorae-svg:XBoomer" }
//
// While it exists the frontend is active for the appearance service: the first time its
// windowDecoration is used (or, when empty, what is chosen now is kept), later the user's own
// choice for this frontend; what the user chooses while it runs is remembered for it. It ends with
// the object (the shell quits, the frontend is switched).

#include <QObject>
#include <QQmlParserStatus>
#include <QtQml/qqmlregistration.h>

namespace MaiaAppearance {

class AppearanceSource;

class FrontendLook : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_ELEMENT

    // The frontend's name, the same on every start ("Lumen", "XPLuna")
    Q_PROPERTY(QString frontend READ frontend WRITE setFrontend NOTIFY frontendChanged)
    // Its default window decoration, "<engine>:<name>"; "" keeps what is chosen
    Q_PROPERTY(QString windowDecoration READ windowDecoration WRITE setWindowDecoration NOTIFY windowDecorationChanged)

public:
    explicit FrontendLook(QObject *parent = nullptr);
    ~FrontendLook() override;

    QString frontend() const { return m_frontend; }
    void setFrontend(const QString &frontend);
    QString windowDecoration() const { return m_windowDecoration; }
    void setWindowDecoration(const QString &themeId);

    void classBegin() override {}
    void componentComplete() override;

Q_SIGNALS:
    void frontendChanged();
    void windowDecorationChanged();

private:
    void update();

    AppearanceSource *m_source;
    QString m_frontend;
    QString m_windowDecoration;
    bool m_complete = false;
    int m_handle;
    bool m_active = false;
};

} // namespace MaiaAppearance
