import QtQuick
import QtQuick.Controls.Basic
import ca.qc.sat.qmlcomponents

// One input-to-output connection. Square-cornered and gapless: adjacent cells
// share their rules, so the grid reads as a table rather than as loose tiles.
//
// Connected uses the same green as the switches in the lists, so "on" looks the
// same everywhere.
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
    readonly property string rangeText:
        !ranged ? "all sources"
                : "sources " + (srcMin < 0 ? "1" : srcMin) + "–" + (srcMax < 0 ? "∞" : srcMax)

    signal toggled
    signal editRequested

    color: routed ? Theme.buttonBgActive
         : hover.hovered ? Theme.backgroundColorTertiary
                         : Theme.backgroundColorSecondary

    Behavior on color {
        ColorAnimation { duration: Theme.animationDuration / 2 }
    }

    // Right, then up: the turn is what reads as routing, and no font is
    // guaranteed to carry the glyph.
    Canvas {
        anchors.centerIn: parent
        width: 24
        height: 24
        visible: root.routed
        antialiasing: true

        readonly property color stroke: Theme.textColorOnAccent
        onStrokeChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = stroke;
            ctx.fillStyle = stroke;
            ctx.lineWidth = 2;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            const left = 4, turn = 16, bottom = 19, top = 8;
            ctx.beginPath();
            ctx.moveTo(left, bottom);
            ctx.lineTo(turn, bottom);
            ctx.lineTo(turn, top);
            ctx.stroke();

            ctx.beginPath();
            ctx.moveTo(turn, top - 5);
            ctx.lineTo(turn - 4.5, top + 1.5);
            ctx.lineTo(turn + 4.5, top + 1.5);
            ctx.closePath();
            ctx.fill();
        }
    }

    // The offset and a narrowed range change what the arrow means, so both are
    // legible without hovering.
    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        visible: root.routed && root.sourceOffset !== 0
        text: "+" + root.sourceOffset
        color: Theme.textColorOnAccent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
    }

    Rectangle {
        visible: root.routed && root.ranged
        width: 7
        height: 7
        radius: 3.5
        color: Theme.textColorOnAccent
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 4
    }

    // Shared rules.
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Theme.borderColor
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.borderColor
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
