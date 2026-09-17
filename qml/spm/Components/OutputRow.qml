import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// One output device, and the selected input's route to it. Columns line up
// with InputRow so the two lists read as one table.
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

    implicitHeight: 52
    color: Theme.backgroundColorSecondary
    border.color: Theme.borderColor
    border.width: 1
    radius: Theme.borderRadius

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        spacing: Theme.spacing

        CustomSwitch {
            checked: root.routed
            onToggled: root.routedToggled(checked)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 120
            spacing: 0

            DeviceField {
                Layout.fillWidth: true
                committed: root.name
                onCommit: value => root.nameEdited(value)
            }

            CustomLabel {
                visible: root.alsoFedBy !== ""
                text: "also fed by " + root.alsoFedBy
                color: Theme.textColorSecondary
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        DeviceField {
            Layout.preferredWidth: 120
            committed: root.host
            onCommit: value => root.hostEdited(value)
        }

        DeviceField {
            Layout.preferredWidth: 80
            committed: String(root.port)
            horizontalAlignment: Text.AlignHCenter
            validator: IntValidator { bottom: 1; top: 65535 }
            onCommit: value => root.portEdited(value)
        }

        CustomComboBox {
            Layout.preferredWidth: 195
            model: root.protocols
            currentIndex: Math.max(0, root.protocols.indexOf(root.protocol))
            onActivated: root.protocolEdited(currentText)
        }

        // Source range and offset together: two numbers that only mean
        // anything side by side, and neither fits the row.
        RowButton {
            Layout.preferredWidth: 120
            text: root.routeText
            enabled: root.routed
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.routeEditRequested()
        }

        RowButton {
            Layout.preferredWidth: 80
            text: "Remove"
            onClicked: root.removeRequested()
        }
    }
}
