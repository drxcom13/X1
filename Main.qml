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
    property bool hornActive: false
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

    // Re-send the bistable states after (re)connecting
    Connections {
        target: BleLink
        function onConnectedChanged() {
            if (BleLink.connected) {
                BleLink.sendCommand(root.lightsOn ? "LIGHT_ON" : "LIGHT_OFF")
                BleLink.sendCommand(root.running ? "START" : "STOP")
            }
        }
    }

    // Large rectangular button with an icon above the text
    component ControlButton: Button {
        id: btn
        property url iconSource
        property color baseColor: "#2b2f36"
        property color activeColor: "#3fa7ff"

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
                    color: "white"
                }
            }
        }

        background: Rectangle {
            radius: 6
            color: btn.down || btn.checked ? btn.activeColor : btn.baseColor
            border.color: "#59616d"
            border.width: 2
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
        color: "#1e1f22"

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
                color: "#99000000"
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
                    color: "white"
                    font.pixelSize: 17
                }

                Label {
                    text: "JP: " + Math.round(rightStick.px * 100)
                          + ", " + Math.round(rightStick.py * 100)
                    color: "white"
                    font.pixelSize: 17
                }

                Label {
                    text: "Lights: " + (root.lightsOn ? "ON" : "OFF")
                    color: root.lightsOn ? "#ffd54f" : "white"
                    font.pixelSize: 17
                }

                Label {
                    text: "State: " + (root.running ? "RUN" : "STOP")
                    color: root.running ? "lightgreen" : "#e5483f"
                    font.pixelSize: 17
                }

                Label {
                    text: "Battery: 87%"
                    color: "lightgreen"
                    font.pixelSize: 17
                }

                Label {
                    text: "BT: " + (BleLink.connected ? BleLink.deviceName : "—")
                    color: BleLink.connected ? "lightgreen" : "#e5483f"
                    font.pixelSize: 15
                }

                Label {
                    text: "Cmd: " + BleLink.lastCommand
                    color: "#8a909a"
                    font.pixelSize: 14
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
            color: "#25272b"

            Row {
                anchors.centerIn: parent
                spacing: 16

                ControlButton {
                    width: root.buttonWidth
                    height: root.buttonHeight
                    // Bistable START/STOP: shows the action the next press performs
                    text: root.running ? "STOP" : "START"
                    iconSource: root.running ? "icons/stop.svg" : "icons/start.svg"
                    baseColor: root.running ? "#b3261e" : "#2e7d32"
                    activeColor: root.running ? "#e5483f" : "#43a047"
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
                    activeColor: "#c9a227"
                    checkable: true
                    checked: root.lightsOn
                    // Bistable: each press toggles the state, the state is sent
                    onToggled: root.lightsOn = checked
                }

                ControlButton {
                    width: root.buttonWidth
                    height: root.buttonHeight
                    text: "Horn"
                    iconSource: "icons/horn.svg"
                    onPressedChanged: root.hornActive = pressed
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
