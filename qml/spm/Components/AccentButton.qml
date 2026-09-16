import QtQuick
import QtQuick.Controls.Basic
import ca.qc.sat.qmlcomponents

// Filled action button. The shared CustomButton is sidebar navigation — its
// `isActive` state draws a tab indicator — so committing and destructive
// actions get this instead.
Button {
    id: control

    // "primary" for the committing action, "danger" for a destructive one.
    property string variant: "primary"

    readonly property color baseColor: variant === "danger" ? Theme.errorColor
                                                            : Theme.primaryColor

    implicitHeight: Theme.buttonHeight
    implicitWidth: 90
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeBody

    background: Rectangle {
        radius: Theme.borderRadius
        color: !control.enabled ? Theme.buttonBgInactive
             : control.pressed  ? Qt.darker(control.baseColor, 1.2)
             : control.hovered  ? Qt.lighter(control.baseColor, 1.15)
                                : control.baseColor

        Behavior on color {
            ColorAnimation { duration: Theme.animationDuration / 2 }
        }
    }

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.enabled ? Theme.textColorOnAccent : Theme.textColorSecondary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
