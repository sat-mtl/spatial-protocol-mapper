import QtQml
import QtQuick

QtObject {
    // Font sizes - responsive with maximum caps
    // Large: Section titles (bold)
    readonly property real fontLarge: 10
    // Medium: Regular text, labels, buttons, inputs
    readonly property real fontMedium: 8
    // Small: Secondary text, small buttons, checkbox labels
    readonly property real fontSmall: 8

    // Font families
    readonly property string fontMonospace: "Consolas, Monaco, monospace"
}
