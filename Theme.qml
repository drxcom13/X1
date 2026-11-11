// Theme.qml — colours taken from the X1 app icon (deep navy, blue and cyan).
// Dark enough to use at night, with a little colour so the UI is not flat black.
pragma Singleton
import QtQuick

QtObject {
    // Background
    readonly property color bgTop: "#0a1a31"
    readonly property color bgBottom: "#040b17"
    readonly property color glow: "#1aa8ff"          // faint arcs in the background

    // Surfaces (buttons, panels, dialogs)
    readonly property color bar: "#06101f"
    readonly property color surface: "#0e2140"
    readonly property color surfaceHigh: "#15305a"
    readonly property color border: "#22508a"
    readonly property color borderSoft: "#183a66"

    // Accents
    readonly property color accent: "#19c3ff"         // cyan, like the "1" in the logo
    readonly property color accentStrong: "#1b8ee0"   // pressed / checked
    readonly property color accentDeep: "#0f5fae"

    // Text
    readonly property color text: "#eaf5ff"
    readonly property color textMuted: "#8fa6c4"
    readonly property color textDim: "#5f7896"

    // States
    readonly property color ok: "#4fd88f"
    readonly property color warn: "#ffd54f"
    readonly property color error: "#ff5a5f"
    readonly property color startBase: "#17663f"
    readonly property color startActive: "#22915a"
    readonly property color stopBase: "#8f1f26"
    readonly property color stopActive: "#c4323a"
    readonly property color lightsActive: "#b38a12"

    // Video area
    readonly property color video: "#020710"
    readonly property color overlay: "#b3040b17"
}
