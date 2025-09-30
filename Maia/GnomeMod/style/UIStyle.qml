pragma Singleton

import QtQuick

QtObject {
    id: uiStyle

    //top panel colors
    readonly property color colorTopPanelBackground: "#131313"


    readonly property color primaryColor: "red"
    //readonly property color accentColor: "#0073e5"
    readonly property color accentColor: "#e95420"
    readonly property color accentLightColor: "#ef8661"
    readonly property color disabledTextColor: "#9c9c9c"
    readonly property color disabledButtonColor: "#ececec"

    //control board fonts
    readonly property color colorControlBoardFont: "red"
    readonly property color colorControlBoardIcon: "#3d3d3d"
    readonly property color colorControlBoardIconActive: "#FFFFFF"
    readonly property real pointSizeControlBoardFont: 10
    readonly property string familyControlBoardFont: "Noto Sans"

    //control board background color
    readonly property color colorControlBoardButtonBackground: "#e3e3e3"

    //control board colors
    // readonly property color colorButtonBatteryLevel: "#e6dcda"
    // readonly property color colorButtonBatteryLevelIcon : "#845248"

    // readonly property color colorButtonScreenshot: "#ccf2dd"
    // readonly property color colorButtonScreenshotIcon : "#00be55"

    // readonly property color colorButtonSystemSettings: "#ccedfd"
    // readonly property color colorButtonSystemSettingsIcon : "#00a4f4"

    // readonly property color colorButtonLock: "#eddbf4"
    // readonly property color colorButtonLockIcon : "#a44cc6"

    // readonly property color colorButtonPower: "#ffddd1"
    // readonly property color colorButtonPowerIcon : "#ff5317"

    readonly property color colorButtonBatteryLevel: colorControlBoardButtonBackground
    readonly property color colorButtonBatteryLevelIcon : colorControlBoardIcon

    readonly property color colorButtonScreenshot: colorControlBoardButtonBackground
    readonly property color colorButtonScreenshotIcon : colorControlBoardIcon

    readonly property color colorButtonSystemSettings: colorControlBoardButtonBackground
    readonly property color colorButtonSystemSettingsIcon : colorControlBoardIcon

    readonly property color colorButtonLock: colorControlBoardButtonBackground
    readonly property color colorButtonLockIcon : colorControlBoardIcon

    readonly property color colorButtonPower: colorControlBoardButtonBackground
    readonly property color colorButtonPowerIcon : colorControlBoardIcon
    
}
