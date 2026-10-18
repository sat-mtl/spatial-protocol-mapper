import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// The protocol column of a device row: the picker, a button for the handler's
// settings when it declares any, and a marker when the handler is in trouble.
// Protocols are picked by id but shown by name, hence the two parallel lists.
RowLayout {
    id: root

    property string protocol: ""
    property var protocolIds: []
    property var protocolNames: []
    property bool hasParams: false
    // A handler problem (not loaded, threw); empty when fine.
    property string error: ""

    signal protocolEdited(string id)
    signal paramsEditRequested

    spacing: 4

    CustomComboBox {
        Layout.fillWidth: true
        Layout.minimumWidth: 60
        model: root.protocolNames
        currentIndex: Math.max(0, root.protocolIds.indexOf(root.protocol))
        onActivated: index => root.protocolEdited(root.protocolIds[index])
    }

    CustomLabel {
        visible: root.error !== ""
        text: "!"
        font.bold: true
        color: Theme.errorColor
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: 12

        ToolTip.visible: errorHover.hovered
        ToolTip.text: root.error
        HoverHandler { id: errorHover }
    }

    RowButton {
        visible: root.hasParams
        Layout.preferredWidth: 36
        text: "…"
        onClicked: root.paramsEditRequested()

        ToolTip.visible: paramsHover.hovered
        ToolTip.delay: 400
        ToolTip.text: "Handler settings"
        HoverHandler { id: paramsHover }
    }
}
