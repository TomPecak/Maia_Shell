import QtQuick

// The sun or the moon of the light / dark mode, drawn (no icon theme has both in the same style)
Canvas {
    id: glyph

    property bool moon: false
    property color ink: "white"

    onInkChanged: requestPaint()
    onMoonChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = ink
        ctx.strokeStyle = ink
        const c = width / 2
        const r = width / 20   // the drawing is made for 20 px
        if (moon) {
            // A disc with a disc cut out of its upper right part
            ctx.beginPath()
            ctx.arc(c, c, 7.5 * r, 0, 2 * Math.PI)
            ctx.fill()
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath()
            ctx.arc(c + 4.5 * r, c - 3.5 * r, 6.5 * r, 0, 2 * Math.PI)
            ctx.fill()
        } else {
            // A disc and eight rays
            ctx.beginPath()
            ctx.arc(c, c, 4 * r, 0, 2 * Math.PI)
            ctx.fill()
            ctx.lineWidth = 1.8 * r
            ctx.lineCap = "round"
            for (let i = 0; i < 8; ++i) {
                const angle = i * Math.PI / 4
                ctx.beginPath()
                ctx.moveTo(c + Math.cos(angle) * 6.8 * r, c + Math.sin(angle) * 6.8 * r)
                ctx.lineTo(c + Math.cos(angle) * 9 * r, c + Math.sin(angle) * 9 * r)
                ctx.stroke()
            }
        }
    }
}
