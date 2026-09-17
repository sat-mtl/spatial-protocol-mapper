import QtQuick
import QtQuick.Controls.Basic
import ca.qc.sat.qmlcomponents
import spm

// One input-to-output connection. Square-cornered and gapless so adjacent
// cells share their rules.
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
    readonly property bool annotated: routed && (ranged || sourceOffset !== 0)
    readonly property string routeText: Format.route(srcMin, srcMax, sourceOffset)
    readonly property string cellText: Format.annotation(srcMin, srcMax, sourceOffset)

    signal toggled
    signal editRequested

    color: routed ? Theme.buttonBgActive
         : hover.hovered ? Theme.backgroundColorTertiary
                         : Theme.backgroundColorSecondary

    Behavior on color {
        ColorAnimation { duration: Theme.animationDuration / 2 }
    }

    // Drawn rather than a glyph: no font is guaranteed to carry it.
    Canvas {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.annotated ? -7 : 0
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

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: parent.width - 8
        visible: root.annotated
        text: root.cellText
        color: Theme.textColorOnAccent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
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
    ToolTip.text: root.inputName + " to " + root.outputName + "\n"
                  + (root.routed ? root.routeText : "not connected")

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.toggled()
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.editRequested()
    }
}
