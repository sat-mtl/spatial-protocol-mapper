import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// One output device in the list. Presentation only — it reports intent through
// signals and never touches the engine, so the same row serves the basic view
// and (later) the per-input tabs.
Rectangle {
    id: root

    property string name: ""
    property string host: ""
    property int port: 0
    property string protocol: ""
    property bool active: true
    property int sourceOffset: 0

    signal activeToggled(bool value)
    signal offsetEdited(int value)
    signal removeRequested

    implicitHeight: 52
    color: root.active ? Theme.backgroundColorTertiary : Theme.backgroundColorSecondary
    border.color: Theme.borderColor
    border.width: 1
    radius: Theme.borderRadius

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        spacing: Theme.spacing

        CustomSwitch {
            checked: root.active
            onToggled: root.activeToggled(checked)
        }

        CustomLabel {
            text: root.name
            font.bold: true
            Layout.preferredWidth: 140
            elide: Text.ElideRight
        }

        CustomLabel {
            text: root.protocol
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
            Layout.preferredWidth: 120
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
            text: "Source offset"
            color: Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
        }

        CustomSpinBox {
            id: offsetBox
            Layout.preferredWidth: 110
            from: 0
            to: 9999
            value: root.sourceOffset
            // `live: false` would defer to editingFinished; the list is small
            // enough that committing per step keeps the wire in sync with what
            // is on screen.
            onValueModified: root.offsetEdited(value)
        }

        AccentButton {
            text: "Remove"
            variant: "danger"
            onClicked: root.removeRequested()
        }
    }
}
