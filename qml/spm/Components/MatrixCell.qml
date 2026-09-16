import QtQuick
import QtQuick.Controls.Basic
import ca.qc.sat.qmlcomponents

// One input-to-output connection in the matrix.
//
// A cell is binary at a glance — connected or not. An offset or a narrowed
// source range is a real routing decision, so it is marked rather than hidden:
// the offset reads in the cell, a narrowed range gets a corner dot, and the
// tooltip spells both out. Editing them happens in the dialog behind a
// right-click, because three controls do not fit in 44 pixels.
Rectangle {
    id: root

    property bool routed: false
    property int sourceOffset: 0
    // -1 on either bound means every source.
    property int srcMin: -1
    property int srcMax: -1
    property string inputName: ""
    property string outputName: ""

    readonly property bool ranged: srcMin >= 0 || srcMax >= 0
    readonly property bool modified: routed && (sourceOffset !== 0 || ranged)
    readonly property string rangeText:
        !ranged ? "all sources"
                : "sources " + (srcMin < 0 ? "1" : srcMin) + "–" + (srcMax < 0 ? "∞" : srcMax)

    signal toggled
    signal editRequested

    color: !routed ? Theme.backgroundColorSecondary
         : modified ? Qt.darker(Theme.primaryColor, 1.25)
                    : Theme.primaryColor
    border.color: hover.hovered ? Theme.primaryColor : Theme.borderColor
    border.width: hover.hovered ? 2 : 1
    radius: 4

    Behavior on color {
        ColorAnimation { duration: Theme.animationDuration / 2 }
    }

    Text {
        anchors.centerIn: parent
        visible: root.routed
        text: root.sourceOffset !== 0
              ? (root.sourceOffset > 0 ? "+" : "") + root.sourceOffset
              : "●"
        color: Theme.textColorOnAccent
        font.family: Theme.fontFamily
        font.pixelSize: root.sourceOffset !== 0 ? Theme.fontSizeSmall : Theme.fontSizeBody
        font.bold: true
    }

    // Corner dot: this route does not carry every source.
    Rectangle {
        visible: root.routed && root.ranged
        width: 7
        height: 7
        radius: 3.5
        color: Theme.textColorOnAccent
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 3
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    ToolTip.visible: hover.hovered
    ToolTip.delay: 400
    ToolTip.text: root.inputName + " → " + root.outputName + "\n"
                  + (root.routed
                     ? root.rangeText
                       + (root.sourceOffset !== 0 ? ", offset " + root.sourceOffset : "")
                       + "\nright-click to edit"
                     : "not connected — click to connect")

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.toggled()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.editRequested()
    }
}
