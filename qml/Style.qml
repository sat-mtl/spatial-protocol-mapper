import QtQml
import QtQuick

QtObject {
    readonly property real fontRatio: Qt.platform.os === "osx" ? 96. / 72. : 1.
    // Font sizes - responsive with maximum caps
    // Large: Section titles (bold)
    readonly property real fontLarge: 12 * fontRatio
    // Medium: Regular text, labels, buttons, inputs
    readonly property real fontMedium: 10 * fontRatio
    // Small: Secondary text, small buttons, checkbox labels
    readonly property real fontSmall: 10 * fontRatio

    // Font families
    readonly property string fontSans: "DM Sans"
    readonly property string fontMonospace: "IBM Plex Mono"
}
