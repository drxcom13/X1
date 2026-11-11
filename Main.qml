import QtQuick
import QtQuick.Controls.Basic

Window {
    id: root
    width: 1280
    height: 720
    visible: true
    title: "X1"

    property bool lightsOn: false
    property bool hornActive: false

    // Same size for both sticks, sized for a thumb
    readonly property real stickRadius: Math.min(width * 0.12, height * 0.17)
    readonly property real buttonWidth: 170
    readonly property real buttonHeight: 120

    onLightsOnChanged: BleLink.sendCommand(lightsOn ? "LIGHT_ON" : "LIGHT_OFF")

    SetupDialog {
        id: setupDialog
    }

    // Re-send the lights state after (re)connecting
    Connections {
        target: BleLink
        function onConnectedChanged() {
            if (BleLink.connected)
                BleLink.sendCommand(root.lightsOn ? "LIGHT_ON" : "LIGHT_OFF")
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

        // CENTER — Telemetry / Status, between the sticks
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: buttonBar.top
            anchors.left: leftStick.right
            anchors.right: rightStick.left
            anchors.margins: 30
            radius: 16
            color: "#2b2f36"

            Column {
                anchors.centerIn: parent
                spacing: 10

                Label {
                    text: "JL: " + Math.round(leftStick.px * 100)
                          + ", " + Math.round(leftStick.py * 100)
                    color: "white"
                    font.pixelSize: 22
                }

                Label {
                    text: "JP: " + Math.round(rightStick.px * 100)
                          + ", " + Math.round(rightStick.py * 100)
                    color: "white"
                    font.pixelSize: 22
                }

                Label {
                    text: "Lights: " + (root.lightsOn ? "ON" : "OFF")
                    color: root.lightsOn ? "#ffd54f" : "white"
                    font.pixelSize: 22
                }

                Label {
                    text: "Battery: 87%"
                    color: "lightgreen"
                    font.pixelSize: 22
                }

                Label {
                    text: "BT: " + (BleLink.connected ? BleLink.deviceName : "—")
                    color: BleLink.connected ? "lightgreen" : "#e5483f"
                    font.pixelSize: 18
                }

                Label {
                    text: "Cmd: " + BleLink.lastCommand
                    color: "#8a909a"
                    font.pixelSize: 16
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
                spacing: 20

                ControlButton {
                    width: root.buttonWidth
                    height: root.buttonHeight
                    text: "Setup"
                    iconSource: "icons/setup.svg"
                    onClicked: setupDialog.open()
                }

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
                    text: "STOP"
                    iconSource: "icons/stop.svg"
                    baseColor: "#b3261e"
                    activeColor: "#e5483f"
                    onPressed: BleLink.sendCommand("STOP_ON")
                    onReleased: BleLink.sendCommand("STOP_OFF")
                    onCanceled: BleLink.sendCommand("STOP_OFF")

                    onClicked: {
                        leftStick.reset()
                        rightStick.reset()
                    }
                }
            }
        }
    }
}
