#pragma once

#include <QString>

class QQmlEngine;

// A frontend is a package: <root>/shell/Main.qml is the shell entry point and the root itself is a QML
// module (qmldir "module <URI>") with the parts shared by the shell and the app faces: theme, components,
// assets. QML finds a module by name only in a directory named after its URI, and the frontend directories
// are named freely ("Ubuntu 24.04"), so the module is exposed through a symlink <URI> -> <root> in a private
// runtime directory added to the engine import paths. Shell files use "import <URI>" for the shared parts
// and relative imports for their own.
class FrontendModules
{
public:
    FrontendModules() = default;
    // Removes the symlinks (never the frontend directories they point to)
    ~FrontendModules();
    Q_DISABLE_COPY_MOVE(FrontendModules)

    // Finds the frontend a QML file belongs to (the nearest parent directory with shell/Main.qml and a
    // qmldir declaring the module) and makes its module importable by name in the engine. Used by the
    // shell for shell/Main.qml and by the client processes of MProxyWindow for their window files.
    bool registerForFile(QQmlEngine &engine, const QString &qmlFilePath);

private:
    // Directory with symlinks <module URI> -> frontend root, one per process
    QString m_modulesDir;
};
