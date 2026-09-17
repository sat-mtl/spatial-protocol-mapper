import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Live OSC traffic. Deliberately not the shared LogView: this pane is fed by a
// bounded ring buffer drained at a user-set rate, because the unthrottled
// version locked the UI under a few hundred sources per second (issue #7).
Pane {
    id: root

    required property var controller
    property alias messageMonitor: monitorText

    // Theme has no monospace token yet; a fixed-width face matters here because
    // the log is columnar. Candidate to move upstream.
    readonly property string monoFont: "IBM Plex Mono"

    padding: 0
    background: Rectangle { color: Theme.backgroundColor }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacing

        SectionHeader { text: "Messages" }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.padding

            CustomSwitch {
                text: "Received"
                checked: root.controller.settings.logReceivedMessages
                onToggled: root.controller.settings.logReceivedMessages = checked
            }

            CustomSwitch {
                text: "Sent"
                checked: root.controller.settings.logSentMessages
                onToggled: root.controller.settings.logSentMessages = checked
            }

            CustomLabel {
                text: "Max display rate"
                color: Theme.textColorSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            CustomSpinBox {
                Layout.preferredWidth: 140
                from: 10
                to: 10000
                stepSize: 50
                value: Math.max(10, Math.min(root.controller.settings.monitorMaxRate, 10000))
                onValueModified: root.controller.settings.monitorMaxRate = value
            }

            CustomLabel {
                text: "msg/s"
                color: Theme.textColorSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            Item { Layout.fillWidth: true }

            CustomButton {
                Layout.preferredWidth: 90
                height: Theme.buttonHeight
                text: "Clear"
                onClicked: root.controller.clearLog()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.backgroundColorSecondary
            border.color: Theme.borderColor
            border.width: 1
            radius: Theme.borderRadius
            clip: true

            ScrollView {
                anchors.fill: parent
                anchors.margins: 1

                TextArea {
                    id: monitorText
                    readOnly: true
                    selectByMouse: true
                    color: Theme.textColor
                    font.family: root.monoFont
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: TextArea.Wrap
                    padding: Theme.spacing

                    background: Rectangle { color: "transparent" }
                }
            }

            CustomLabel {
                anchors.centerIn: parent
                visible: monitorText.length === 0
                color: Theme.textColorSecondary
                text: "No messages"
            }
        }
    }
}
