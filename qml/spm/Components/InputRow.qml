import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// One row of the inputs table. Columns come from Columns so the header and the
// outputs table line up with it; inputs bind on every interface, so their
// address cell is empty and the route cell carries the bind error.
Rectangle {
    id: root

    property string name: ""
    property int port: 0
    property string protocol: "Auto"
    property bool listening: false
    property string error: ""
    property var protocols: []
    // Which input the outputs table is showing routes for.
    property bool selected: false

    signal listeningToggled(bool value)
    signal nameEdited(string value)
    signal portEdited(string value)
    signal protocolEdited(string value)
    signal removeRequested
    signal selectRequested

    implicitHeight: 48
    color: Theme.backgroundColorSecondary

    // Shared edges: only the bottom rule, so consecutive rows read as a table
    // rather than as a stack of cards.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.separatorColor
    }

    // The selected input is what the outputs table below refers to.
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
            text: "any address"
            color: Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
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

        CustomLabel {
            Layout.preferredWidth: Columns.route
            text: root.error
            color: Theme.errorColor
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        RowButton {
            Layout.preferredWidth: Columns.action
            text: "Remove"
            onClicked: root.removeRequested()
        }
    }
}
