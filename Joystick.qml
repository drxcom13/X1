// Joystick.qml
import QtQuick

Item {
    id: root
    property real px: 0.0   // -1..1 (right = +1)
    property real py: 0.0   // -1..1 (up = +1)
    property real stickRadius: 120
    readonly property real knobRadius: stickRadius * 0.3
    // Maximum distance the knob centre can travel from the joystick centre
    readonly property real travel: stickRadius - knobRadius

    width: stickRadius * 2
    height: stickRadius * 2

    signal changed()

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: width / 2
        color: "#404854"
    }

    Rectangle {
        id: knob
        width: root.knobRadius * 2
        height: width
        radius: width / 2
        color: "#d0d4dd"
        // Position is derived from px/py, so the model is the single source of truth
        x: root.width / 2 - root.knobRadius + root.px * root.travel
        y: root.height / 2 - root.knobRadius - root.py * root.travel
    }

    MouseArea {
        anchors.fill: parent

        function setFromPoint(mx, my) {
            var dx = mx - width / 2
            var dy = my - height / 2
            var len = Math.sqrt(dx * dx + dy * dy)
            // Clamp to a circle, not a square
            if (len > root.travel && len > 0) {
                dx *= root.travel / len
                dy *= root.travel / len
            }
            root.px = dx / root.travel
            root.py = -dy / root.travel   // invert Y: up is positive
            root.changed()
        }

        onPressed: (mouse) => setFromPoint(mouse.x, mouse.y)
        onPositionChanged: (mouse) => setFromPoint(mouse.x, mouse.y)
        onReleased: root.reset()
        onCanceled: root.reset()
    }

    function reset() {
        px = 0
        py = 0
        changed()
    }
}
