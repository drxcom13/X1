import QtQuick
import QtCore
import QtQuick.Controls.Basic

Window {
    id: root
    width: 1280
    height: 720
    visible: true
    title: "X1"

    property bool lightsOn: false
    property bool running: false     // START/STOP state

    // Same size for both sticks, sized for a thumb
    readonly property real stickRadius: Math.min(width * 0.12, height * 0.17)
    // 7 buttons in the bottom bar must fit the window width
    readonly property real buttonWidth: Math.min(170, (width - 60 - 6 * 16) / 7)
    readonly property real buttonHeight: 120

    onLightsOnChanged: BleLink.sendCommand(lightsOn ? "LIGHT_ON" : "LIGHT_OFF")
    onRunningChanged: {
        BleLink.sendCommand(running ? "START" : "STOP")
        if (!running) {
            leftStick.reset()
            rightStick.reset()
        }
    }

    // Persistent user settings
    Settings {
        id: settings
        property string rtspUrl: ""
    }

    SetupDialog {
        id: setupDialog
        rtspUrl: settings.rtspUrl
        onRtspUrlEdited: (url) => settings.rtspUrl = url
    }

    Connections {
        target: BleLink
        function onConnectedChanged() {
            if (BleLink.connected) {
                // Re-send the bistable states after (re)connecting
                BleLink.sendCommand(root.lightsOn ? "LIGHT_ON" : "LIGHT_OFF")
                BleLink.sendCommand(root.running ? "START" : "STOP")
            } else {
                // Link lost: disarm, so a reconnect never restarts the model
                // on its own. The operator has to press START again.
                root.running = false
            }
        }
    }

    // App leaves the foreground (Home, app switcher, incoming call, screen off):
    // stop the model. On the desktop only when the window is hidden/minimised.
    Connections {
        target: Qt.application
        function onStateChanged() {
            const state = Qt.application.state
            if (state === Qt.ApplicationSuspended || state === Qt.ApplicationHidden
                    || (Qt.platform.os === "android" && state === Qt.ApplicationInactive))
                root.running = false
        }
    }

    // Android Back: first press stops the model, a second one within 2 s exits
    Timer {
        id: backTimer
        interval: 2000
    }

    // Large rectangular button with an icon above the text
    component ControlButton: Button {
        id: btn
        property url iconSource
        property color baseColor: Theme.surface
        property color activeColor: Theme.accentStrong
        property color borderColor: Theme.border

        font.pixelSize: 20
        font.bold: true

        contentItem: Item {
            Column {
                anchors.centerIn: parent
                spacing: 8

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: btn.iconSource.toString() !== ""
                    source: btn.iconSource
                    width: 56
                    height: 56
                    sourceSize: Qt.size(56, 56)
                    fillMode: Image.PreserveAspectFit
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: btn.text
                    font: btn.font
                    color: Theme.text
                }
            }
        }

        background: Rectangle {
            radius: 10
            color: btn.down || btn.checked ? btn.activeColor : btn.baseColor
            border.color: btn.down || btn.checked ? Theme.accent : btn.borderColor
            border.width: 2
            // Faint top highlight, like the glossy edge of the icon
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#1affffff" }
                    GradientStop { position: 0.5; color: "#00ffffff" }
                }
            }
        }
    }

    // Momentary function button: Fn_ON on press, Fn_OFF on release
    component FunctionButton: ControlButton {
        font.pixelSize: 30
        onPressed: BleLink.sendCommand(text + "_ON")
        onReleased: BleLink.sendCommand(text + "_OFF")
        onCanceled: BleLink.sendCommand(text + "_OFF")
    }

    Rectangle {
        anchors.fill: parent
        // Receives the Android Back key (key events propagate up to here)
        focus: true
        Keys.onBackPressed: (event) => {
            event.accepted = true
            root.running = false
            if (backTimer.running)
                Qt.quit()
            else
                backTimer.start()
        }
        // Deep navy gradient from the icon; dark enough for night use
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bgTop }
            GradientStop { position: 1.0; color: Theme.bgBottom }
        }

        // Two faint arcs echoing the icon, behind everything else
        Canvas {
            id: backdrop
            anchors.fill: parent
            opacity: 0.22
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2
                var r = Math.max(width, height) * 0.62
                var cy = height * 0.18 + r
                ctx.lineCap = "round"
                ctx.strokeStyle = Theme.glow
                ctx.lineWidth = 3
                ctx.beginPath()
                ctx.arc(cx, cy, r, Math.PI * 1.18, Math.PI * 1.82)
                ctx.stroke()
                ctx.lineWidth = 2
                ctx.globalAlpha = 0.6
                ctx.beginPath()
                ctx.arc(cx, cy + height * 0.12, r * 1.06, Math.PI * 1.25, Math.PI * 1.75)
                ctx.stroke()
            }
        }

        // Discreet logo under the left joystick
        Image {
            source: "icons/x1_logo.png"
            anchors.horizontalCenter: leftStick.horizontalCenter
            anchors.top: leftStick.bottom
            anchors.topMargin: Math.max(8, (buttonBar.y - leftStick.y - leftStick.height - height) / 2)
            width: Math.min(72, Math.max(0, buttonBar.y - leftStick.y - leftStick.height - 16))
            height: width
            visible: width >= 32
            sourceSize: Qt.size(144, 144)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            opacity: 0.55
        }

        // LEFT joystick (JL) — top-left corner
        Joystick {
            id: leftStick
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 30
            stickRadius: root.stickRadius
            onChanged: BleLink.setLeftStick(Math.round(leftStick.px * 100),
                                            Math.round(leftStick.py * 100))
        }

        // RIGHT joystick (JP) — top-right corner
        Joystick {
            id: rightStick
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 30
            stickRadius: root.stickRadius
            onChanged: BleLink.setRightStick(Math.round(rightStick.px * 100),
                                             Math.round(rightStick.py * 100))
        }

        // CENTER — live video between the sticks, telemetry as an overlay
        VideoView {
            id: video
            anchors.top: parent.top
            anchors.bottom: buttonBar.top
            anchors.left: leftStick.right
            anchors.right: rightStick.left
            anchors.margins: 30
            source: settings.rtspUrl

            // Semi-transparent backdrop behind the telemetry text
            Rectangle {
                x: telemetry.x - 10
                y: telemetry.y - 8
                width: telemetry.width + 20
                height: telemetry.height + 16
                radius: 8
                color: Theme.overlay
                border.color: Theme.borderSoft
                border.width: 1
            }

            Column {
                id: telemetry
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 22
                spacing: 4

                Label {
                    text: "JL: " + Math.round(leftStick.px * 100)
                          + ", " + Math.round(leftStick.py * 100)
                    color: Theme.text
                    font.pixelSize: 17
                }

                Label {
                    text: "JP: " + Math.round(rightStick.px * 100)
                          + ", " + Math.round(rightStick.py * 100)
                    color: Theme.text
                    font.pixelSize: 17
                }

                Label {
                    text: "Lights: " + (root.lightsOn ? "ON" : "OFF")
                    color: root.lightsOn ? Theme.warn : Theme.text
                    font.pixelSize: 17
                }

                Label {
                    text: "State: " + (root.running ? "RUN" : "STOP")
                    color: root.running ? Theme.ok : Theme.error
                    font.pixelSize: 17
                }

                Label {
                    text: "BT: " + (BleLink.connected ? BleLink.deviceName : "—")
                    color: BleLink.connected ? Theme.accent : Theme.error
                    font.pixelSize: 15
                }

                Label {
                    text: "Cmd: " + BleLink.lastCommand
                    color: Theme.textMuted
                    font.pixelSize: 14
                }
            }

            // Hint after the first Back press
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                width: backHint.implicitWidth + 32
                height: backHint.implicitHeight + 20
                radius: height / 2
                color: Theme.overlay
                border.color: Theme.border
                visible: backTimer.running

                Label {
                    id: backHint
                    anchors.centerIn: parent
                    text: "Stopped. Press Back again to exit"
                    color: Theme.text
                    font.pixelSize: 18
                }
            }
        }

        // BOTTOM strip — all buttons, centered
        Rectangle {
            id: buttonBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.buttonHeight + 40
            color: Theme.bar

            // Thin cyan line on top of the bar
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Theme.accentDeep }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 16

                ControlButton {
                    width: root.buttonWidth
                    height: root.buttonHeight
                    // Bistable START/STOP: shows the action the next press performs
                    text: root.running ? "STOP" : "START"
                    iconSource: root.running ? "icons/stop.svg" : "icons/start.svg"
                    baseColor: root.running ? Theme.stopBase : Theme.startBase
                    activeColor: root.running ? Theme.stopActive : Theme.startActive
                    borderColor: root.running ? Theme.stopActive : Theme.startActive
                    onClicked: root.running = !root.running
                }

                FunctionButton { text: "F1"; width: root.buttonWidth; height: root.buttonHeight }
                FunctionButton { text: "F2"; width: root.buttonWidth; height: root.buttonHeight }
                FunctionButton { text: "F3"; width: root.buttonWidth; height: root.buttonHeight }

                ControlButton {
                    width: root.buttonWidth
                    height: root.buttonHeight
                    text: "Lights"
                    iconSource: "icons/light.svg"
                    activeColor: Theme.lightsActive
                    // Bistable: each press toggles root.lightsOn, which is sent.
                    // Not checkable, so `checked` stays bound to the state.
                    checked: root.lightsOn
                    onClicked: root.lightsOn = !root.lightsOn
                }

                ControlButton {
                    width: root.buttonWidth
                    height: root.buttonHeight
                    text: "Horn"
                    iconSource: "icons/horn.svg"
                    onPressed: BleLink.sendCommand("HORN_ON")
                    onReleased: BleLink.sendCommand("HORN_OFF")
                    onCanceled: BleLink.sendCommand("HORN_OFF")
                }

                ControlButton {
                    width: root.buttonWidth
                    height: root.buttonHeight
                    text: "Setup"
                    iconSource: "icons/setup.svg"
                    onClicked: setupDialog.open()
                }
            }
        }
    }
}
