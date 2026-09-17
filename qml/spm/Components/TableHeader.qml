import QtQuick
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Column titles for a device table. Mirrors the row layout exactly — same
// widths from Columns, same margins — so the two line up by construction.
Item {
    id: root

    // Inputs have no address of their own and outputs have no bind state, so
    // each table labels the two variable columns itself.
    property string hostTitle: ""
    property string routeTitle: ""

    implicitHeight: 26

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing * 2
        anchors.rightMargin: Theme.spacing * 2
        spacing: Theme.spacing

        component Title: CustomLabel {
            color: Theme.textColorSecondary
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        Title {
            Layout.preferredWidth: Columns.toggle
            text: "On"
        }

        Title {
            Layout.fillWidth: true
            Layout.minimumWidth: Columns.minName
            text: "Name"
        }

        Title {
            Layout.preferredWidth: Columns.host
            text: root.hostTitle
        }

        Title {
            Layout.preferredWidth: Columns.port
            horizontalAlignment: Text.AlignHCenter
            text: "Port"
        }

        Title {
            Layout.preferredWidth: Columns.protocol
            text: "Protocol"
        }

        Title {
            Layout.preferredWidth: Columns.route
            horizontalAlignment: Text.AlignHCenter
            text: root.routeTitle
        }

        Item { Layout.preferredWidth: Columns.action }
    }
}
