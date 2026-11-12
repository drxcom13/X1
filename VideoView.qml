// VideoView.qml — live RTSP video (Qt Multimedia, FFmpeg backend)
import QtQuick
import QtQuick.Controls.Basic
import QtMultimedia

Rectangle {
    id: view
    property string source: ""          // e.g. rtsp://192.168.4.1:8554/stream
    property string errorText: ""
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
                                    && (player.mediaStatus === MediaPlayer.BufferedMedia
                                        || player.mediaStatus === MediaPlayer.BufferingMedia)

    color: Theme.video
    radius: 16
    clip: true
    border.color: Theme.borderSoft
    border.width: 1

    // Time of the last decoded frame (or of the last restart), for the stall watchdog
    property double lastFrameMs: 0
    readonly property int stallTimeoutMs: 8000

    function restart() {
        retryTimer.stop()
        lastFrameMs = Date.now()
        player.stop()
        // Clear the source first: assigning the same URL again is a no-op in
        // MediaPlayer, so a failed stream would never be reopened.
        player.source = ""
        if (source !== "") {
            player.source = source
            player.play()
        } else {
            errorText = ""
        }
    }

    onSourceChanged: { errorText = ""; restart() }
    Component.onCompleted: restart()

    MediaPlayer {
        id: player
        videoOutput: videoOut

        onErrorOccurred: (error, errorString) => {
            view.errorText = errorString
            retryTimer.restart()
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.BufferedMedia)
                view.errorText = ""          // picture is back
            // Stream ended, dropped or could not be opened: try to reconnect
            if (mediaStatus === MediaPlayer.EndOfMedia || mediaStatus === MediaPlayer.InvalidMedia)
                retryTimer.restart()
        }
    }

    VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    Connections {
        target: videoOut.videoSink
        function onVideoFrameChanged() { view.lastFrameMs = Date.now() }
    }

    // A stream that silently stops (e.g. RTP over UDP after a Wi-Fi drop) often
    // raises no error and the picture just freezes. Restart when no frame has
    // arrived for stallTimeoutMs, also while still trying to connect.
    Timer {
        interval: 1000
        repeat: true
        running: view.source !== "" && player.playbackState === MediaPlayer.PlayingState
        onTriggered: {
            if (Date.now() - view.lastFrameMs > view.stallTimeoutMs) {
                view.errorText = "No video frames for "
                        + Math.round(view.stallTimeoutMs / 1000) + " s"
                view.restart()
            }
        }
    }

    // Reconnect every few seconds while the stream is unavailable
    Timer {
        id: retryTimer
        interval: 3000
        onTriggered: view.restart()
    }

    // Status shown while there is no picture
    Column {
        anchors.centerIn: parent
        spacing: 8
        visible: !view.playing

        // Faded logo while there is no picture
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "icons/x1_logo.png"
            width: Math.min(120, view.height * 0.25)
            height: width
            sourceSize: Qt.size(240, 240)
            fillMode: Image.PreserveAspectFit
            mipmap: true
            opacity: 0.35
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: view.source === "" ? "No video"
                  : view.errorText !== "" ? "Video unavailable"
                  : "Connecting to video..."
            color: Theme.text
            font.pixelSize: 22
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, view.width - 40)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: view.source === "" ? "Set the RTSP address in Setup"
                  : view.errorText !== "" ? view.errorText + "\nRetrying..."
                  : view.source
            color: Theme.textMuted
            font.pixelSize: 16
        }
    }
}
