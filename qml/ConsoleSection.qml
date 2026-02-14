import QtCore
import QtQuick.Controls.Universal
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Score.UI as UI
import "./Engine.js" as Engine

GroupBox {
    property alias messageMonitor: messageMonitor
    SplitView.preferredHeight: 200
    SplitView.minimumHeight: 80
    visible: appSettings.monitorVisible
    title: "Message Monitor"

    background: Rectangle {
        color: "#2a2a2a"
        border.color: "#3a3a3a"
        radius: 4
    }

    label: Label {
        text: parent.title
        color: "#ffffff"
        font.bold: true
        font.pixelSize: Math.min(14, window.height * 0.025)
        padding: 5
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 15

            CheckBox {
                id: logReceivedCheckbox
                checked: appSettings.logReceivedMessages
                onToggled: appSettings.logReceivedMessages = checked

                indicator: Rectangle {
                    x: 0
                    anchors.verticalCenter: parent.contentItem.verticalCenter
                    implicitWidth: 18
                    implicitHeight: 18
                    color: parent.checked ? "#4a8a4a" : "#3a3a3a"
                    border.color: "#5a5a5a"
                    radius: 2

                    Label {
                        anchors.centerIn: parent
                        text: "✓"
                        color: "#ffffff"
                        visible: parent.parent.checked
                        font.pixelSize: 10
                    }
                }

                contentItem: Label {
                    text: "Log Received"
                    color: "#ffffff"
                    leftPadding: logReceivedCheckbox.indicator.width + 6
                    font.pixelSize: Math.min(11, window.height * 0.018)
                }
            }

            CheckBox {
                id: logSentCheckbox
                checked: appSettings.logSentMessages
                onToggled: appSettings.logSentMessages = checked

                indicator: Rectangle {
                    x: 0
                    anchors.verticalCenter: parent.contentItem.verticalCenter
                    implicitWidth: 18
                    implicitHeight: 18
                    color: parent.checked ? "#4a8a4a" : "#3a3a3a"
                    border.color: "#5a5a5a"
                    radius: 2

                    Label {
                        anchors.centerIn: parent
                        text: "✓"
                        color: "#ffffff"
                        visible: parent.parent.checked
                        font.pixelSize: 10
                    }
                }

                contentItem: Label {
                    text: "Log Sent"
                    color: "#ffffff"
                    leftPadding: logSentCheckbox.indicator.width + 6
                    font.pixelSize: Math.min(11, window.height * 0.018)
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                text: "Clear"
                Layout.preferredWidth: 60
                Layout.preferredHeight: 22
                onClicked: messageMonitor.clear()

                background: Rectangle {
                    color: parent.hovered ? "#5a5a5a" : "#4a4a4a"
                    border.color: "#6a6a6a"
                    radius: 2
                }

                contentItem: Label {
                    text: parent.text
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Math.min(10, window.height * 0.016)
                }
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            background: Rectangle {
                color: "#1a1a1a"
                radius: 2
            }

            TextArea {
                id: messageMonitor
                readOnly: true
                selectByMouse: true
                color: "#00ff00"
                font.family: "Consolas, Monaco, monospace"
                font.pixelSize: Math.min(11, window.height * 0.018)
                wrapMode: TextArea.Wrap
                padding: 8

                background: Rectangle {
                    color: "transparent"
                }
            }
        }
    }
}
