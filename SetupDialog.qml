// SetupDialog.qml — Bluetooth (BLE UART) device selection and video source
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Popup {
    id: dialog
    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(parent ? parent.width * 0.7 : 800, 800)
    height: parent ? parent.height * 0.85 : 600
    padding: 20

    // RTSP address of the video stream; Main.qml stores it
    property string rtspUrl: ""
    signal rtspUrlEdited(string url)

    // Basic-style controls (Button, TextField, BusyIndicator) take their colours from here
    palette.window: Theme.surface
    palette.windowText: Theme.text
    palette.base: Theme.bgBottom
    palette.text: Theme.text
    palette.placeholderText: Theme.textDim
    palette.button: Theme.surfaceHigh
    palette.buttonText: Theme.text
    palette.mid: Theme.accentStrong          // pressed button
    palette.dark: Theme.accent               // focus frame, busy indicator
    palette.highlight: Theme.accent
    palette.highlightedText: Theme.bgBottom
    palette.light: Theme.surfaceHigh
    palette.midlight: Theme.border

    // Basic Button does not dim itself when disabled; make that visible
    component DialogButton: Button {
        opacity: enabled ? 1.0 : 0.4
    }

    background: Rectangle {
        radius: 16
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.surface }
            GradientStop { position: 1.0; color: Theme.bgBottom }
        }
        border.color: Theme.border
        border.width: 2
    }

    Overlay.modal: Rectangle { color: "#99020610" }

    onOpened: {
        rtspField.text = dialog.rtspUrl
        if (!BleLink.connected && BleLink.devices.length === 0)
            BleLink.startScan()
    }

    contentItem: ColumnLayout {
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Image {
                source: "icons/x1_logo.png"
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                sourceSize: Qt.size(96, 96)
                fillMode: Image.PreserveAspectFit
                mipmap: true
            }

            Label {
                text: "Setup"
                color: Theme.text
                font.pixelSize: 26
                font.bold: true
                Layout.fillWidth: true
            }

            DialogButton {
                text: "Close"
                font.pixelSize: 18
                Layout.preferredHeight: 56
                Layout.preferredWidth: 120
                onClicked: dialog.close()
            }
        }

        // Video source
        Label {
            text: "Video (RTSP)"
            color: Theme.text
            font.pixelSize: 20
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            TextField {
                id: rtspField
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                font.pixelSize: 18
                placeholderText: "rtsp://192.168.4.1:8554/stream"
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                                  | Qt.ImhNoPredictiveText
                onAccepted: applyButton.clicked()
            }

            DialogButton {
                id: applyButton
                text: "Apply"
                font.pixelSize: 18
                Layout.preferredHeight: 56
                Layout.preferredWidth: 120
                onClicked: {
                    rtspField.focus = false
                    dialog.rtspUrlEdited(rtspField.text.trim())
                }
            }
        }

        // Bluetooth
        Label {
            text: "Bluetooth"
            color: Theme.text
            font.pixelSize: 20
            font.bold: true
        }

        Label {
            text: BleLink.status
            color: BleLink.connected ? Theme.ok : Theme.textMuted
            font.pixelSize: 18
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            DialogButton {
                text: BleLink.scanning ? "Stop scan" : "Scan"
                font.pixelSize: 18
                Layout.preferredHeight: 64
                Layout.fillWidth: true
                enabled: !BleLink.busy
                onClicked: BleLink.scanning ? BleLink.stopScan() : BleLink.startScan()
            }

            DialogButton {
                text: "Disconnect"
                font.pixelSize: 18
                Layout.preferredHeight: 64
                Layout.fillWidth: true
                enabled: BleLink.connected || BleLink.busy
                onClicked: BleLink.disconnectFromDevice()
            }
        }

        BusyIndicator {
            running: BleLink.scanning || BleLink.busy
            visible: running
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 48
        }

        ListView {
            id: deviceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: BleLink.devices

            delegate: ItemDelegate {
                id: deviceDelegate
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 72
                enabled: !BleLink.busy

                background: Rectangle {
                    radius: 8
                    color: deviceDelegate.down ? Theme.accentStrong : Theme.surfaceHigh
                    border.color: Theme.borderSoft
                    border.width: 1
                }

                contentItem: ColumnLayout {
                    spacing: 2
                    Label {
                        text: deviceDelegate.modelData.name
                        color: Theme.text
                        font.pixelSize: 20
                        font.bold: true
                    }
                    Label {
                        text: deviceDelegate.modelData.address
                              + "   RSSI " + deviceDelegate.modelData.rssi + " dBm"
                        color: Theme.textMuted
                        font.pixelSize: 14
                    }
                }

                onClicked: BleLink.connectToDevice(deviceDelegate.index)
            }

            Label {
                anchors.centerIn: parent
                visible: deviceList.count === 0 && !BleLink.scanning
                text: "No devices. Press Scan."
                color: Theme.textMuted
                font.pixelSize: 18
            }
        }
    }
}
