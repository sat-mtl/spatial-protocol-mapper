import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// One row of the outputs table, carrying the selected input's route to it.
Rectangle {
    id: root

    property string name: ""
    property string host: ""
    property int port: 0
    property string protocol: ""
    property var protocols: []

    property bool routed: true
    property int sourceOffset: 0
    // -1 on either bound means every source.
    property int srcMin: -1
    property int srcMax: -1
    readonly property string routeText: Format.route(srcMin, srcMax, sourceOffset)

    signal routedToggled(bool value)
    signal nameEdited(string value)
    signal hostEdited(string value)
    signal portEdited(string value)
    signal protocolEdited(string value)
    signal routeEditRequested
    signal removeRequested

    implicitHeight: 48
    color: Theme.backgroundColorSecondary

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.separatorColor
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing * 2
        anchors.rightMargin: Theme.spacing * 2
        spacing: Theme.spacing

        CustomSwitch {
            Layout.preferredWidth: Columns.toggle
            checked: root.routed
            onToggled: root.routedToggled(checked)
        }

        DeviceField {
            Layout.fillWidth: true
            Layout.minimumWidth: Columns.minName
            committed: root.name
            onCommit: value => root.nameEdited(value)
        }

        DeviceField {
            Layout.preferredWidth: Columns.host
            committed: root.host
            onCommit: value => root.hostEdited(value)
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

        // Source range and offset together: two numbers that only mean
        // anything side by side, and neither fits the row.
        RowButton {
            Layout.preferredWidth: Columns.route
            text: root.routeText
            enabled: root.routed
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.routeEditRequested()
        }

        RowButton {
            Layout.preferredWidth: Columns.action
            text: "Remove"
            onClicked: root.removeRequested()
        }
    }
}
