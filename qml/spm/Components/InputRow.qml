import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// One input device. Columns line up with OutputRow so the two lists read as
// one table; inputs bind on every interface, so the host column is empty.
Rectangle {
    id: root

    property string name: ""
    property int port: 0
    property string protocol: "Auto"
    property bool listening: false
    property string error: ""
    property var protocols: []
    // Which input the output switches below refer to.
    property bool selected: false

    signal listeningToggled(bool value)
    signal nameEdited(string value)
    signal portEdited(string value)
    signal protocolEdited(string value)
    signal removeRequested
    signal selectRequested

    implicitHeight: 52
    color: Theme.backgroundColorSecondary
    border.color: root.selected ? Theme.primaryColor : Theme.borderColor
    border.width: 1
    radius: Theme.borderRadius

    TapHandler { onTapped: root.selectRequested() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        spacing: Theme.spacing

        CustomSwitch {
            checked: root.listening
            onToggled: root.listeningToggled(checked)
        }

        DeviceField {
            Layout.fillWidth: true
            Layout.minimumWidth: 120
            committed: root.name
            onCommit: value => root.nameEdited(value)
        }

        // Inputs bind on 0.0.0.0; the slot keeps the columns lined up.
        Item { Layout.preferredWidth: 120 }

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

        // Where the outputs carry their route button.
        CustomLabel {
            Layout.preferredWidth: 120
            text: root.error
            color: Theme.errorColor
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        RowButton {
            Layout.preferredWidth: 80
            text: "Remove"
            onClicked: root.removeRequested()
        }
    }
}
