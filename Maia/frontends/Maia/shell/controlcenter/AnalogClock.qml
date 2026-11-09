import QtQuick

import MaiaFrontend

// A small clock face: twelve ticks (the quarters longer), the hour and minute hands, a dot in the
// middle; in the colors of the mode
Canvas {
    id: clock

    property date time: new Date()

    readonly property color ink: Theme.label
    readonly property color faint: Theme.secondaryLabel
    readonly property color face: Theme.fill

    onTimeChanged: requestPaint()
    onInkChanged: requestPaint()
    onFaceChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const c = width / 2
        const r = width / 2 - 1

        ctx.fillStyle = face
        ctx.beginPath()
        ctx.arc(c, c, r, 0, 2 * Math.PI)
        ctx.fill()

        ctx.lineCap = "round"
        for (let i = 0; i < 12; ++i) {
            const quarter = i % 3 === 0
            const angle = i * Math.PI / 6
            const outer = r - 2
            const inner = outer - (quarter ? r * 0.2 : r * 0.1)
            ctx.strokeStyle = quarter ? ink : faint
            ctx.lineWidth = quarter ? Math.max(1.5, r / 14) : Math.max(1, r / 22)
            ctx.beginPath()
            ctx.moveTo(c + Math.sin(angle) * inner, c - Math.cos(angle) * inner)
            ctx.lineTo(c + Math.sin(angle) * outer, c - Math.cos(angle) * outer)
            ctx.stroke()
        }

        const minutes = time.getMinutes()
        const hours = time.getHours() % 12 + minutes / 60
        const hand = function (angle, length, lineWidth) {
            ctx.lineWidth = lineWidth
            ctx.beginPath()
            ctx.moveTo(c, c)
            ctx.lineTo(c + Math.sin(angle) * length, c - Math.cos(angle) * length)
            ctx.stroke()
        }
        ctx.strokeStyle = ink
        hand(hours * Math.PI / 6, r * 0.5, Math.max(2, r / 8))
        hand(minutes * Math.PI / 30, r * 0.76, Math.max(1.5, r / 12))

        ctx.fillStyle = ink
        ctx.beginPath()
        ctx.arc(c, c, Math.max(1.5, r / 10), 0, 2 * Math.PI)
        ctx.fill()
    }
}
