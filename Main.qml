import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: root
    width: 1280
    height: 720
    visible: true
    title: "X1"

    property real throttle: 0.0

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
                    onChanged: {
                        // steering.x, steering.y
                    }
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
                            text: "Battery: 87%"
                            color: "lightgreen"
                            font.pixelSize: 22
                        }
                    }
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

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 20

                        Label {
                            text: "Throttle"
                            color: "white"
                            font.pixelSize: 22
                        }

                        Slider {
                            id: throttleSlider
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            orientation: Qt.Vertical
                            from: -1
                            to: 1
                            value: 0

                            onValueChanged: {
                                root.throttle = throttleSlider.value
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Button {
                                text: "Brake"
                                Layout.fillWidth: true
                                onClicked: throttleSlider.value = 0
                            }

                            Button {
                                text: "Reverse"
                                Layout.fillWidth: true
                                onClicked: throttleSlider.value = -0.5
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        text: "Lights"
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Horn"
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "STOP"
                        Layout.fillWidth: true

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
