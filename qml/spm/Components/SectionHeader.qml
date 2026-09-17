import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents

// Titled separator: a label with a rule running to the right edge.
ColumnLayout {
    id: root

    property string text: ""

    Layout.fillWidth: true
    spacing: 4

    CustomLabel {
        text: root.text
        font.bold: true
        font.pixelSize: Theme.fontSizeSubtitle
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.separatorColor
    }
}
