import QtQuick
import QtQuick.Controls.Basic
import ca.qc.sat.qmlcomponents

// One input-to-output connection.
//
// Connected cells use the same green as the switches in the lists, so "on"
// looks the same everywhere. The arrow is drawn rather than set as a glyph:
// the turn is what reads as routing, and no font is guaranteed to carry it.
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

    color: routed ? Theme.buttonBgActive : Theme.backgroundColorSecondary
    border.color: hover.hovered ? Theme.primaryColor : Theme.borderColor
    border.width: hover.hovered ? 2 : 1
    radius: 4

    Behavior on color {
        ColorAnimation { duration: Theme.animationDuration / 2 }
    }

    // Right, then up.
    Canvas {
        id: arrow
        anchors.centerIn: parent
        width: 22
        height: 22
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

            const left = 3, turn = 15, bottom = 18, top = 7;
            ctx.beginPath();
            ctx.moveTo(left, bottom);
            ctx.lineTo(turn, bottom);
            ctx.lineTo(turn, top);
            ctx.stroke();

            // Arrowhead at the top of the upstroke.
            ctx.beginPath();
            ctx.moveTo(turn, top - 5);
            ctx.lineTo(turn - 4, top + 1);
            ctx.lineTo(turn + 4, top + 1);
            ctx.closePath();
            ctx.fill();
        }
    }

    // The offset displaces the arrow's meaning, so it is shown on the cell.
    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 3
        visible: root.routed && root.sourceOffset !== 0
        text: "+" + root.sourceOffset
        color: Theme.textColorOnAccent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
    }

    // A route that does not carry every source.
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
