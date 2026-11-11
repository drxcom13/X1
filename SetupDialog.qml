// SetupDialog.qml — Bluetooth (BLE UART) device selection
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

    background: Rectangle {
        radius: 16
        color: "#2b2f36"
        border.color: "#59616d"
        border.width: 2
    }

    onOpened: {
        if (!BleLink.connected && BleLink.devices.length === 0)
            BleLink.startScan()
    }

    contentItem: ColumnLayout {
        spacing: 14

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: "Setup — Bluetooth"
                color: "white"
                font.pixelSize: 26
                font.bold: true
                Layout.fillWidth: true
            }

            Button {
                text: "Close"
                font.pixelSize: 18
                Layout.preferredHeight: 56
                Layout.preferredWidth: 120
                onClicked: dialog.close()
            }
        }

        Label {
            text: BleLink.status
            color: BleLink.connected ? "lightgreen" : "#c8ccd4"
            font.pixelSize: 18
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                text: BleLink.scanning ? "Stop scan" : "Scan"
                font.pixelSize: 18
                Layout.preferredHeight: 64
                Layout.fillWidth: true
                enabled: !BleLink.busy
                onClicked: BleLink.scanning ? BleLink.stopScan() : BleLink.startScan()
            }

            Button {
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
                    color: deviceDelegate.down ? "#3fa7ff" : "#404854"
                }

                contentItem: ColumnLayout {
                    spacing: 2
                    Label {
                        text: deviceDelegate.modelData.name
                        color: "white"
                        font.pixelSize: 20
                        font.bold: true
                    }
                    Label {
                        text: deviceDelegate.modelData.address
                              + "   RSSI " + deviceDelegate.modelData.rssi + " dBm"
                        color: "#c8ccd4"
                        font.pixelSize: 14
                    }
                }

                onClicked: BleLink.connectToDevice(deviceDelegate.index)
            }

            Label {
                anchors.centerIn: parent
                visible: deviceList.count === 0 && !BleLink.scanning
                text: "No devices. Press Scan."
                color: "#8a909a"
                font.pixelSize: 18
            }
        }
    }
}
