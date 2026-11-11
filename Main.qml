import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Window {
    id: root
    width: 1280
    height: 720
    visible: true
    title: "X1"

    property real throttle: 0.0      // 0..1
    property bool lightsOn: false
    property bool hornActive: false

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

        Layout.fillWidth: true
        Layout.preferredHeight: 130
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

        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 20

            // LEFT CONTROL ZONE — Steering Joystick
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.40
                radius: 20
                color: "#2b2f36"

                Joystick {
                    id: steering
                    anchors.centerIn: parent
                    stickRadius: Math.min(parent.width, parent.height) * 0.35
                    onChanged: BleLink.setSteering(Math.round(steering.px * 100),
                                                   Math.round(steering.py * 100))
                }
            }

            // CENTER ZONE — Telemetry / Status
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.20
                spacing: 16

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: "#2b2f36"

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Label {
                            text: "Speed: " + Math.round(root.throttle * 100) + "%"
                            color: "white"
                            font.pixelSize: 22
                        }

                        Label {
                            text: "Steering: " + Math.round(steering.px * 100) + "%"
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

                ControlButton {
                    text: "Setup"
                    iconSource: "icons/setup.svg"
                    onClicked: setupDialog.open()
                }
            }

            // RIGHT CONTROL ZONE — Throttle + Buttons
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * 0.40
                spacing: 20

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 20
                    color: "#2b2f36"

                    // Throttle readout, left of the slider, aligned to the top
                    Column {
                        anchors.top: parent.top
                        anchors.right: throttleColumn.left
                        anchors.topMargin: 20
                        anchors.rightMargin: 16
                        spacing: 4

                        Label {
                            anchors.right: parent.right
                            text: "Throttle"
                            color: "white"
                            font.pixelSize: 20
                        }

                        Label {
                            anchors.right: parent.right
                            text: Math.round(root.throttle * 100) + "%"
                            color: "white"
                            font.pixelSize: 40
                            font.bold: true
                        }
                    }

                    // Throttle column pinned to the right edge of the panel
                    ColumnLayout {
                        id: throttleColumn
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 20
                        width: 160
                        spacing: 12

                        // Wide vertical throttle, 0..100 %
                        Slider {
                            id: throttleSlider
                            Layout.fillHeight: true
                            Layout.fillWidth: true
                            orientation: Qt.Vertical
                            from: 0
                            to: 1
                            stepSize: 0.01
                            value: 0

                            onValueChanged: {
                                root.throttle = throttleSlider.value
                                BleLink.setThrottle(Math.round(throttleSlider.value * 100))
                            }

                            background: Rectangle {
                                x: (throttleSlider.width - width) / 2
                                y: throttleSlider.topPadding
                                width: 90
                                height: throttleSlider.availableHeight
                                radius: 12
                                color: "#404854"

                                // Filled part from the bottom up
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: throttleSlider.position * parent.height
                                    radius: 12
                                    color: "#3fa7ff"
                                }
                            }

                            handle: Rectangle {
                                x: (throttleSlider.width - width) / 2
                                y: throttleSlider.topPadding
                                   + throttleSlider.visualPosition * (throttleSlider.availableHeight - height)
                                width: 150
                                height: 56
                                radius: 10
                                color: throttleSlider.pressed ? "#ffffff" : "#d0d4dd"
                                border.color: "#1e1f22"
                                border.width: 2
                            }
                        }

                        ControlButton {
                            text: "Brake"
                            Layout.preferredHeight: 60
                            font.pixelSize: 18
                            onPressed: BleLink.sendCommand("BRAKE_ON")
                            onReleased: BleLink.sendCommand("BRAKE_OFF")
                            onCanceled: BleLink.sendCommand("BRAKE_OFF")
                            onClicked: throttleSlider.value = 0
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    ControlButton {
                        text: "Lights"
                        iconSource: "icons/light.svg"
                        activeColor: "#c9a227"
                        checkable: true
                        checked: root.lightsOn
                        // Bistable: each press toggles the state, the state is sent
                        onToggled: root.lightsOn = checked
                    }

                    ControlButton {
                        text: "Horn"
                        iconSource: "icons/horn.svg"
                        onPressedChanged: root.hornActive = pressed
                        onPressed: BleLink.sendCommand("HORN_ON")
                        onReleased: BleLink.sendCommand("HORN_OFF")
                        onCanceled: BleLink.sendCommand("HORN_OFF")
                    }

                    ControlButton {
                        text: "STOP"
                        iconSource: "icons/stop.svg"
                        baseColor: "#b3261e"
                        activeColor: "#e5483f"
                        onPressed: BleLink.sendCommand("STOP_ON")
                        onReleased: BleLink.sendCommand("STOP_OFF")
                        onCanceled: BleLink.sendCommand("STOP_OFF")

                        onClicked: {
                            throttleSlider.value = 0
                            steering.reset()
                        }
                    }
                }
            }
        }
    }
}
