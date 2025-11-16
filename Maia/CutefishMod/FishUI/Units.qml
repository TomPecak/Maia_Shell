pragma Singleton

import QtQuick

QtObject {
    id: units

     property int test : 10

    /**
     * units.smallSpacing is the amount of spacing that should be used around smaller UI elements,
     * for example as spacing in Columns. Internally, this size depends on the size of
     * the default font as rendered on the screen, so it takes user-configured font size and DPI
     * into account.
     */
    // property int smallSpacing: Math.floor(gridUnit / 4)
    property int smallSpacing: 6

    /**
     * units.largeSpacing is the amount of spacing that should be used inside bigger UI elements,
     * for example between an icon and the corresponding text. Internally, this size depends on
     * the size of the default font as rendered on the screen, so it takes user-configured font
     * size and DPI into account.
     */
    property int largeSpacing: smallSpacing * 2

     /**
      * The ratio between physical and device-independent pixels. This value does not depend on the \
      * size of the configured font. If you want to take font sizes into account when scaling elements,
      * use theme.mSize(theme.defaultFont), units.smallSpacing and units.largeSpacing.
      * The devicePixelRatio follows the definition of "device independent pixel" by Microsoft.
      */
     property real devicePixelRatio: Screen.devicePixelRatio

}
