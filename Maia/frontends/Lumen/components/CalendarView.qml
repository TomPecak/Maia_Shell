import QtQuick
import QtQuick.Layouts

import ".."

// Month calendar: header with the month name and navigation buttons, weekday names
// and a 6 x 7 grid of days. Today is marked with an accent circle. Switching the month
// slides the grid in the direction of the navigation.
Item {
    id: calendar

    // First day of the displayed month
    property date shownMonth: new Date(Shell.now.getFullYear(), Shell.now.getMonth(), 1)
    readonly property var locale: Qt.locale()

    implicitWidth: 7 * 40
    implicitHeight: header.height + weekdays.height + grid.height + 2 * Theme.spacingS

    function showMonth(offset) {
        slide.direction = offset
        shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + offset, 1)
        slide.restart()
    }

    function isSameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    RowLayout {
        id: header

        width: parent.width
        height: 32

        LText {
            Layout.fillWidth: true
            leftPadding: Theme.spacingS
            text: calendar.locale.standaloneMonthName(calendar.shownMonth.getMonth()) + " " + calendar.shownMonth.getFullYear()
            font.pixelSize: Theme.fontBody
            font.weight: Font.DemiBold
        }

        SubtleButton {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            Accessible.name: qsTr("Previous month")
            contentItem: Item { LIcon { anchors.centerIn: parent; iconName: "go-up-symbolic" } }
            onClicked: calendar.showMonth(-1)
        }

        SubtleButton {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            Accessible.name: qsTr("Next month")
            contentItem: Item { LIcon { anchors.centerIn: parent; iconName: "go-up-symbolic"; rotation: 180 } }
            onClicked: calendar.showMonth(1)
        }
    }

    Row {
        id: weekdays

        anchors.top: header.bottom
        anchors.topMargin: Theme.spacingS
        height: 28

        Repeater {
            model: 7

            delegate: LText {
                required property int index

                width: calendar.width / 7
                height: 28
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontCaption
                color: Theme.textSecondary
                // Week starts on the first day of the week of the locale
                text: calendar.locale.dayName((calendar.locale.firstDayOfWeek + index) % 7, Locale.ShortFormat)
            }
        }
    }

    Grid {
        id: grid

        anchors.top: weekdays.bottom
        anchors.topMargin: Theme.spacingS
        columns: 7

        // Offset of the first day of the month in the first row
        readonly property int leadingDays: (calendar.shownMonth.getDay() - calendar.locale.firstDayOfWeek + 7) % 7

        transform: Translate { id: gridShift }

        Repeater {
            model: 42

            delegate: SubtleButton {
                id: day

                required property int index

                readonly property date date: new Date(calendar.shownMonth.getFullYear(), calendar.shownMonth.getMonth(),
                                                      index - grid.leadingDays + 1)
                readonly property bool inMonth: date.getMonth() === calendar.shownMonth.getMonth()
                readonly property bool today: calendar.isSameDay(date, Shell.now)

                width: calendar.width / 7
                height: 40
                radius: height / 2
                padding: 0
                Accessible.name: date.toLocaleDateString(calendar.locale)

                contentItem: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: 34
                        height: 34
                        radius: 17
                        color: Theme.accent
                        visible: day.today
                    }

                    LText {
                        anchors.centerIn: parent
                        text: day.date.getDate()
                        color: day.today ? Theme.onAccent : day.inMonth ? Theme.textPrimary : Theme.textTertiary
                        font.weight: day.today ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }

    // Slide and fade of the grid when the month changes
    ParallelAnimation {
        id: slide

        property int direction: 1

        NumberAnimation {
            target: gridShift; property: "y"
            from: slide.direction * 24; to: 0
            duration: Theme.durationNormal; easing.type: Theme.easingEnter
        }
        NumberAnimation {
            target: grid; property: "opacity"
            from: 0; to: 1
            duration: Theme.durationNormal; easing.type: Theme.easingEnter
        }
    }
}
