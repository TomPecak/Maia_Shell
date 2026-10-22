import QtQuick
import QtQuick.Layouts
import org.kde.layershell 1.0 as LayerShell

import LumenFrontend

// Widgets board on the left side of the screen, between the top edge and the taskbar.
// Real: time, date, processor usage (Maia backend). Mock-ups: weather, agenda, world clocks.
FlyoutWindow {
    id: widgets

    flyoutName: "widgets"
    cardWidth: 440
    stretchCard: true
    edges: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft
    enterOffsetX: -Theme.flyoutOffset
    enterOffsetY: 0

    readonly property bool hasBackend: typeof backend !== "undefined" && backend !== null

    // Processor usage is measured only while the board is open
    onOpenChanged: {
        if (hasBackend)
            backend.measureCpuLoad = open
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingXL
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column

            width: parent.width
            spacing: Theme.spacingM

            // --- Greeting and time ---

            LText {
                text: Shell.greeting + ", " + Shell.userName
                color: Theme.textSecondary
                font.pixelSize: Theme.fontBodyLarge
            }

            LText {
                text: Shell.now.toLocaleTimeString(Qt.locale(), "HH:mm")
                font.pixelSize: Theme.fontDisplay
                font.weight: Font.Light
            }

            LText {
                Layout.bottomMargin: Theme.spacingS
                text: {
                    const date = Shell.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM yyyy")
                    return date.charAt(0).toUpperCase() + date.slice(1)
                }
                color: Theme.textSecondary
            }

            // --- Weather (mock) and processor usage (real) ---

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                WidgetCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    title: qsTr("Weather")
                    iconName: "weather-few-clouds-symbolic"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        RowLayout {
                            spacing: Theme.spacingS

                            LIcon {
                                size: 40
                                iconName: "weather-few-clouds-symbolic"
                                tint: Theme.accent
                            }

                            LText {
                                text: "18°"
                                font.pixelSize: 40
                                font.weight: Font.Light
                            }
                        }

                        LText { text: qsTr("Partly sunny"); font.weight: Font.DemiBold }
                        LText { text: qsTr("Kraków · H 21° L 11°"); font.pixelSize: Theme.fontCaption; color: Theme.textSecondary }
                        Item { Layout.fillHeight: true }
                    }
                }

                WidgetCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    title: qsTr("Processor")
                    iconName: "speedometer-symbolic"

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.spacingXS

                        LText {
                            text: widgets.hasBackend ? Math.round(backend.cpuLoad) + "%" : "–"
                            font.pixelSize: 40
                            font.weight: Font.Light
                        }

                        LText { text: qsTr("Usage, last minute"); font.pixelSize: Theme.fontCaption; color: Theme.textSecondary }

                        Sparkline {
                            id: cpuGraph

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Connections {
                                target: widgets.hasBackend ? backend : null
                                function onCpuLoadChanged() { cpuGraph.addValue(backend.cpuLoad / 100) }
                            }
                        }
                    }
                }
            }

            // --- Agenda (mock) ---

            WidgetCard {
                Layout.fillWidth: true
                Layout.preferredHeight: agenda.implicitHeight + 64
                title: qsTr("Today")
                iconName: "view-calendar-symbolic"

                Column {
                    id: agenda

                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Theme.spacingS

                    Repeater {
                        model: [
                            { time: "10:00", title: qsTr("Stand-up"), place: qsTr("Online") },
                            { time: "13:30", title: qsTr("Design review"), place: qsTr("Room 2.04") },
                            { time: "17:00", title: qsTr("Gym"), place: qsTr("City centre") }
                        ]

                        delegate: RowLayout {
                            required property var modelData

                            width: agenda.width
                            spacing: Theme.spacingM

                            Rectangle {
                                Layout.preferredWidth: 3
                                Layout.fillHeight: true
                                radius: 1.5
                                color: Theme.accent
                            }

                            LText {
                                Layout.preferredWidth: 48
                                text: modelData.time
                                color: Theme.textSecondary
                            }

                            Column {
                                Layout.fillWidth: true
                                LText { text: modelData.title; font.weight: Font.DemiBold }
                                LText { text: modelData.place; font.pixelSize: Theme.fontCaption; color: Theme.textSecondary }
                            }
                        }
                    }
                }
            }

            // --- World clocks (time is real, cities are fixed offsets) ---

            WidgetCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 128
                title: qsTr("World clock")
                iconName: "globe-symbolic"

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.spacingM

                    Repeater {
                        model: [
                            { city: qsTr("London"), offset: 0 },
                            { city: qsTr("New York"), offset: -5 },
                            { city: qsTr("Tokyo"), offset: 9 }
                        ]

                        delegate: Column {
                            required property var modelData

                            Layout.fillWidth: true

                            LText {
                                text: {
                                    const now = Shell.now
                                    const utc = now.getTime() + now.getTimezoneOffset() * 60000
                                    return new Date(utc + modelData.offset * 3600000).toLocaleTimeString(Qt.locale(), "HH:mm")
                                }
                                font.pixelSize: Theme.fontSubtitle
                            }
                            LText { text: modelData.city; font.pixelSize: Theme.fontCaption; color: Theme.textSecondary }
                        }
                    }
                }
            }
        }
    }

    // --- Local components ---

    // Widget: card with a small header (icon and title) and content under it
    component WidgetCard: Card {
        id: widgetCard

        property string title
        property string iconName
        default property alias content: contentArea.data

        Row {
            id: widgetHeader

            x: Theme.spacingL
            y: Theme.spacingM
            spacing: Theme.spacingS

            LIcon { anchors.verticalCenter: parent.verticalCenter; size: 14; iconName: widgetCard.iconName; tint: Theme.textSecondary }
            LText { text: widgetCard.title; font.pixelSize: Theme.fontCaption; color: Theme.textSecondary }
        }

        Item {
            id: contentArea

            anchors.fill: parent
            anchors.topMargin: widgetHeader.y + widgetHeader.height + Theme.spacingS
            anchors.leftMargin: Theme.spacingL
            anchors.rightMargin: Theme.spacingL
            anchors.bottomMargin: Theme.spacingM
        }
    }

    // Line chart of the last values (0..1), newest on the right
    component Sparkline: Canvas {
        id: sparkline

        property var values: []
        property int maxValues: 60

        function addValue(value) {
            const updated = values.slice(-(maxValues - 1))
            updated.push(Math.max(0, Math.min(1, value)))
            values = updated
            requestPaint()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (values.length < 2)
                return

            const step = width / (maxValues - 1)
            const startX = width - (values.length - 1) * step

            ctx.beginPath()
            for (let i = 0; i < values.length; ++i) {
                const x = startX + i * step
                const y = height - values[i] * (height - 2) - 1
                if (i === 0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }
            ctx.lineWidth = 2
            ctx.strokeStyle = Theme.accent
            ctx.lineJoin = "round"
            ctx.stroke()

            // Soft fill under the line
            ctx.lineTo(width, height)
            ctx.lineTo(startX, height)
            ctx.closePath()
            ctx.globalAlpha = 0.18
            ctx.fillStyle = Theme.accent
            ctx.fill()
        }
    }
}
