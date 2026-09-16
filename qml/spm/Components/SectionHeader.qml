import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents

// Titled separator: a subtitle-weight label with a rule running to the right
// edge, used to break the views into labelled bands.
ColumnLayout {
    id: root

    property string text: ""
    property string hint: ""

    Layout.fillWidth: true
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing

        CustomLabel {
            text: root.text
            font.bold: true
            font.pixelSize: Theme.fontSizeSubtitle
        }

        CustomLabel {
            text: root.hint
            visible: root.hint !== ""
            color: Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Item { Layout.fillWidth: root.hint === "" }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separatorColor
    }
}
