import QtQuick
import QtQuick.Controls.Basic
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
    property bool alternate: false

    property bool routed: true
    property int sourceOffset: 0
    // -1 on either bound means every source.
    property int srcMin: -1
    property int srcMax: -1
    // The other inputs feeding this output, empty when it is only fed from the
    // selected one. Without it, unrouting here looks like it did nothing.
    property string alsoFedBy: ""

    readonly property string rangeText:
        (srcMin < 0 && srcMax < 0)
        ? "all sources"
        : (srcMin < 0 ? "1" : srcMin) + "–" + (srcMax < 0 ? "∞" : srcMax)
    readonly property string routeText:
        rangeText + (sourceOffset !== 0 ? "  +" + sourceOffset : "")

    signal routedToggled(bool value)
    signal nameEdited(string value)
    signal hostEdited(string value)
    signal portEdited(string value)
    signal protocolEdited(string value)
    signal routeEditRequested
    signal removeRequested

    implicitHeight: 48
    color: root.alternate ? Qt.darker(Theme.backgroundColorSecondary, 1.12)
                          : Theme.backgroundColorSecondary

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

            // Fed from more than one input: shown on the field so removing the
            // route here cannot look like it did nothing.
            ToolTip.visible: root.alsoFedBy !== "" && fedHover.hovered
            ToolTip.text: "Also fed by " + root.alsoFedBy
            HoverHandler { id: fedHover }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 8
                visible: root.alsoFedBy !== ""
                width: 6
                height: 6
                radius: 3
                color: Theme.textColorSecondary
            }
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
