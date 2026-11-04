import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts

import LumenFrontend

// The base of a page or sub-page: a scrolling column, at most 1000 px wide (long lines are hard
// to read and far from the window edge), with the page's title for the breadcrumb.
Controls.ScrollView {
    id: page

    // Shown in the breadcrumb
    property string title
    default property alias content: column.data

    contentWidth: availableWidth
    clip: true
    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff

    ColumnLayout {
        id: column

        x: Theme.spacingXL
        width: Math.min(page.availableWidth - 2 * Theme.spacingXL, 1000)
        spacing: Theme.spacingXL

        Item { Layout.preferredHeight: 0 }
    }
}
