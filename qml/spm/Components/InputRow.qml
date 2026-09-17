import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// One row of the inputs table. Inputs bind on every interface, so the address
// cell carries the bind error instead.
Rectangle {
    id: root

    property string name: ""
    property int port: 0
    property string protocol: "Auto"
    property bool listening: false
    property string error: ""
    property var protocols: []
    property real scaleX: 1
    property real scaleY: 1
    property real scaleZ: 1
    // Which input the outputs table is showing routes for.
    property bool selected: false

    signal listeningToggled(bool value)
    signal nameEdited(string value)
    signal portEdited(string value)
    signal protocolEdited(string value)
    signal scaleEditRequested
    signal removeRequested
    signal selectRequested

    implicitHeight: 48
    color: Theme.backgroundColorSecondary

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.separatorColor
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        color: Theme.primaryColor
        visible: root.selected
    }

    TapHandler { onTapped: root.selectRequested() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing * 2
        anchors.rightMargin: Theme.spacing * 2
        spacing: Theme.spacing

        CustomSwitch {
            Layout.preferredWidth: Columns.toggle
            checked: root.listening
            onToggled: root.listeningToggled(checked)
        }

        DeviceField {
            Layout.fillWidth: true
            Layout.minimumWidth: Columns.minName
            committed: root.name
            onCommit: value => root.nameEdited(value)
        }

        CustomLabel {
            Layout.preferredWidth: Columns.host
            text: root.error !== "" ? root.error : "any address"
            color: root.error !== "" ? Theme.errorColor : Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight

            ToolTip.visible: root.error !== "" && errorHover.hovered
            ToolTip.text: root.error
            HoverHandler { id: errorHover }
        }

        DeviceField {
            Layout.preferredWidth: Columns.port
            committed: String(root.port)
            horizontalAlignment: Text.AlignHCenter
            validator: IntValidator { bottom: 1; top: 65535 }
            onCommit: value => root.portEdited(value)
        }

        CustomComboBox {
            Layout.preferredWidth: Columns.protocol
            model: root.protocols
            currentIndex: Math.max(0, root.protocols.indexOf(root.protocol))
            onActivated: root.protocolEdited(currentText)
        }

        RowButton {
            Layout.preferredWidth: Columns.route
            text: Format.scale(root.scaleX, root.scaleY, root.scaleZ)
            onClicked: root.scaleEditRequested()
        }

        RowButton {
            Layout.preferredWidth: Columns.action
            text: "Remove"
            onClicked: root.removeRequested()
        }
    }
}
