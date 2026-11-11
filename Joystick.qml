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
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.surfaceHigh }
            GradientStop { position: 1.0; color: Theme.surface }
        }
        border.color: Theme.border
        border.width: 2

        // Travel guide ring
        Rectangle {
            anchors.centerIn: parent
            width: root.travel * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Theme.borderSoft
            border.width: 1
        }
    }

    Rectangle {
        id: knob
        width: root.knobRadius * 2
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f2f9ff" }
            GradientStop { position: 1.0; color: "#a9cbe8" }
        }
        border.color: root.px !== 0 || root.py !== 0 ? Theme.accent : "#6f93b8"
        border.width: 3
        // Position is derived from px/py, so the model is the single source of truth
        x: root.width / 2 - root.knobRadius + root.px * root.travel
        y: root.height / 2 - root.knobRadius - root.py * root.travel
    }

    // MultiPointTouchArea instead of MouseArea: every joystick tracks its own
    // finger, so both sticks can be used at the same time. Mouse works too.
    MultiPointTouchArea {
        anchors.fill: parent
        mouseEnabled: true
        maximumTouchPoints: 1
        touchPoints: [ TouchPoint { id: touch } ]

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

        onPressed: setFromPoint(touch.x, touch.y)
        onUpdated: setFromPoint(touch.x, touch.y)
        onReleased: root.reset()
        onCanceled: root.reset()
    }

    function reset() {
        px = 0
        py = 0
        changed()
    }
}
