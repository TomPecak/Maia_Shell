#pragma once

// Plain values of the appearance state, copied out of Cap'n Proto messages (AppearanceConnection)
// and kept in the GUI thread (AppearanceSource), plus the enumerations QML sees as
// Appearance.Engine.AuroraeSvg, ... with the values of contract/decorations.capnp.

#include <QList>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

namespace MaiaAppearance {

namespace Appearance
{
Q_NAMESPACE
QML_NAMED_ELEMENT(Appearance)
// Always Appearance.Engine.AuroraeSvg: several enumerations share value names (None)
Q_CLASSINFO("RegisterEnumClassesUnscoped", "false")

enum class Engine { AuroraeSvg, AuroraeQml, Kdecoration, Wayfire };
Q_ENUM_NS(Engine)

enum class Origin { System, Maia, User };
Q_ENUM_NS(Origin)

enum class BorderSize { Theme, None, NoSides, Tiny, Normal, Large, VeryLarge, Huge, VeryHuge, Oversized };
Q_ENUM_NS(BorderSize)

enum class ErrorCode { None, NotFound, NotAllowed, InvalidArgument, NotSupported, Unavailable, Failed, AlreadyExists };
Q_ENUM_NS(ErrorCode)
} // namespace Appearance

struct ThemeData {
    QString id;             // "aurorae-svg:XBoomer"
    Appearance::Engine engine = Appearance::Engine::Kdecoration;
    QString name;
    QString description;
    QString author;
    Appearance::Origin origin = Appearance::Origin::System;
    bool available = true;
    QString unavailableReason;
    QString path;
    bool operator==(const ThemeData &) const = default;
};

struct CurrentData {
    QString themeId;
    Appearance::BorderSize borderSize = Appearance::BorderSize::Theme;
    bool confirmed = false;
    QString frontend;
    bool operator==(const CurrentData &) const = default;
};

struct CapabilitiesData {
    QString compositor;
    QList<Appearance::Engine> engines;
    bool borderSizes = false;
    bool install = false;
    bool operator==(const CapabilitiesData &) const = default;
};

// The answer of a call
struct Result {
    Appearance::ErrorCode error = Appearance::ErrorCode::None;
    QString message;
};

} // namespace MaiaAppearance
