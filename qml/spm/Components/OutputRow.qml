import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// One output device as seen from a given input: the route to it (on/off,
// offset, source range) plus the device's own identity. Presentation only —
// it reports intent through signals and never touches the engine.
Rectangle {
    id: root

    property string name: ""
    property string host: ""
    property int port: 0
    property string protocol: ""
    property bool routed: true
    property int sourceOffset: 0
    // -1 on either bound means every source.
    property int srcMin: -1
    property int srcMax: -1
    // Names of the other inputs feeding this output, empty when it is only fed
    // from here. Without it, unrouting on this tab looks like it did nothing.
    property string alsoFedBy: ""

    readonly property bool rangeIsAll: srcMin < 0 && srcMax < 0
    readonly property string rangeText:
        rangeIsAll ? "all sources"
                   : (srcMin < 0 ? "1" : srcMin) + "–" + (srcMax < 0 ? "∞" : srcMax)

    signal routedToggled(bool value)
    signal offsetEdited(int value)
    signal rangeEditRequested
    signal removeRequested

    implicitHeight: 52
    color: root.routed ? Theme.backgroundColorTertiary : Theme.backgroundColorSecondary
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
            Layout.preferredWidth: 150
            spacing: 0

            CustomLabel {
                text: root.name
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            CustomLabel {
                visible: root.alsoFedBy !== ""
                text: "also fed by " + root.alsoFedBy
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        CustomLabel {
            text: root.protocol
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
            Layout.preferredWidth: 115
            elide: Text.ElideRight
        }

        CustomLabel {
            text: root.host + ":" + root.port
            color: Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        CustomLabel {
            text: "Sources"
            color: Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
        }

        CustomButton {
            Layout.preferredWidth: 110
            height: Theme.buttonHeight
            text: root.rangeText
            // A narrowed range is a real routing decision; make it legible at
            // a glance rather than hiding it behind the dialog.
            isActive: !root.rangeIsAll
            enabled: root.routed
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.rangeEditRequested()
        }

        CustomLabel {
            text: "Offset"
            color: Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
        }

        CustomSpinBox {
            Layout.preferredWidth: 105
            from: 0
            to: 9999
            value: root.sourceOffset
            enabled: root.routed
            opacity: enabled ? 1.0 : 0.4
            onValueModified: root.offsetEdited(value)
        }

        AccentButton {
            text: "Remove"
            variant: "danger"
            onClicked: root.removeRequested()
        }
    }
}
