#pragma once

#include <QString>

// Where a Maia version keeps its files. Every version has its own configuration directory, so
// versions installed side by side (/opt/Maia/Maia_<version>) never share or overwrite settings,
// and a new version starts clean:
//
//   $XDG_CONFIG_HOME/maia/<version>/      (~/.config/maia/0.2.0/)
//       maia.conf          QSettings of the shell and Maia Settings (C++ and QML Settings {})
//       maiarc             KConfig of the shell (active frontend, locale)
//       appearance.json    maia-appearance-service (its own copy of this rule, in Rust)
//       wayfire.ini        Wayfire in the "Maia (Wayfire)" session (the session script)
//
// The session scripts and the Rust services compute the same directory; keep them in step.
namespace MaiaPaths
{
// The Maia version this program belongs to, e.g. "0.2.0"
QString version();

// $XDG_CONFIG_HOME/maia/<version>, created if missing
QString configDir();

// A file in configDir()
QString configFile(const QString &name);

// Names the application so that QSettings (and QML's Settings {}) use configDir()/maia.conf:
// Qt puts the file at <config home>/<organization>/<application>.conf, so the organization is
// "maia/<version>" and the application "maia". Call before any QSettings is created.
void setupApplicationNames();
} // namespace MaiaPaths
