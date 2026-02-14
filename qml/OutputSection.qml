import QtCore
import QtQuick.Controls.Universal
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Score.UI as UI
import "./Engine.js" as Engine

GroupBox {
    property alias outputListModel: outputListModel
    SplitView.fillHeight: true
    SplitView.minimumHeight: 200
    title: "Output Devices"

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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 10

        // Add Output Form
        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            TextField {
                id: outputNameField
                Layout.preferredWidth: Math.max(100, Math.min(150, window.width * 0.15))
                color: "#ffffff"
                font.pixelSize: Math.min(12, window.height * 0.02)
                placeholderText: "(Name)"
                placeholderTextColor: "#888"

                background: Rectangle {
                    color: "#3a3a3a"
                    border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                    radius: 2
                }
            }

            TextField {
                id: outputHostField
                Layout.preferredWidth: Math.max(100, Math.min(150, window.width * 0.15))
                text: "127.0.0.1"
                placeholderText: "IP Address"
                color: "#ffffff"
                font.pixelSize: Math.min(12, window.height * 0.02)

                background: Rectangle {
                    color: "#3a3a3a"
                    border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                    radius: 2
                }
            }

            TextField {
                id: outputPortField
                Layout.preferredWidth: Math.max(60, Math.min(100, window.width * 0.1))
                text: "8000"
                placeholderText: "Port"
                color: "#ffffff"
                font.pixelSize: Math.min(12, window.height * 0.02)

                background: Rectangle {
                    color: "#3a3a3a"
                    border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                    radius: 2
                }
            }

            ComboBox {
                id: outputTypeCombo
                Layout.preferredWidth: Math.max(120, Math.min(180, window.width * 0.18))
                model: ["SpatGRIS", "ADM-OSC", "SPAT Revolution"]
                currentIndex: 0

                background: Rectangle {
                    y: 3
                    color: "#3a3a3a"
                    border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                    radius: 2
                    height: outputPortField.height
                }

                contentItem: Label {
                    text: parent.displayText
                    height: 10
                    color: "#ffffff"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                    font.pixelSize: 12
                }
                delegate: ItemDelegate {
                    width: parent.width

                    background: Rectangle {
                        color: parent.hovered ? "#4a4a4a" : "#3a3a3a"
                    }

                    contentItem: Label {
                        text: modelData
                        color: "#ffffff"
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Math.min(12, window.height * 0.02)
                    }
                }
                /*
                indicator: Canvas {
                    x: parent.width - width - 10
                    y: parent.topPadding + (parent.availableHeight - height) / 2
                    width: 12
                    height: 12
                    contextType: "2d"

                    onPaint: {
                        context.reset()
                        context.moveTo(0, 0)
                        context.lineTo(width, 0)
                        context.lineTo(width / 2, height)
                        context.closePath()
                        context.fillStyle = "#888888"
                        context.fill()
                    }
                }*/

            }

            Button {
                text: "Add"
                Layout.preferredWidth: Math.max(50, Math.min(80, window.width * 0.08))

                onClicked: {
                    console.log(outputNameField.text, outputHostField.text, outputPortField.text);
                    if (outputNameField.text && outputHostField.text && outputPortField.text) {
                        Engine.createOutputDevice(outputNameField.text, outputHostField.text, parseInt(outputPortField.text), outputTypeCombo.currentText);
                        outputNameField.clear();
                        outputPortField.text = "8000";
                    }
                }

                background: Rectangle {
                    color: parent.hovered ? "#5a9a5a" : "#4a8a4a"
                    border.color: "#6aaa6a"
                    radius: 2
                }

                contentItem: Label {
                    text: parent.text
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Math.min(12, window.height * 0.02)
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        // Output List
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            background: Rectangle {
                color: "#1a1a1a"
                radius: 2
            }

            ListView {
                model: ListModel {
                    id: outputListModel
                }
                spacing: 2

                delegate: Rectangle {
                    width: ListView.view.width - 10
                    height: 40
                    color: model.active ? "#3a3a3a" : "#2a2a2a"
                    border.color: "#4a4a4a"
                    radius: 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        CheckBox {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            checked: model.active

                            onToggled: {
                                outputDevices[index].active = checked;
                                Engine.updateOutputList();
                                Engine.saveOutputDevices();
                            }

                            indicator: Rectangle {
                                implicitWidth: 20
                                implicitHeight: 20
                                color: parent.checked ? "#4a8a4a" : "#3a3a3a"
                                border.color: "#5a5a5a"
                                radius: 2

                                Label {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "#ffffff"
                                    visible: parent.parent.checked
                                    font.pixelSize: Math.min(12, window.height * 0.02)
                                }
                            }
                        }

                        Label {
                            text: model.name
                            color: "#ffffff"
                            Layout.preferredWidth: Math.max(80, window.width * 0.15)
                            elide: Text.ElideRight
                            font.pixelSize: Math.min(12, window.height * 0.02)
                        }

                        Label {
                            text: `${model.type} - ${model.host}:${model.port}`
                            color: "#aaaaaa"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Math.min(11, window.height * 0.018)
                        }

                        Button {
                            Layout.preferredWidth: Math.max(60, Math.min(80, window.width * 0.08))
                            Layout.preferredHeight: 25
                            text: "Remove"

                            onClicked: Engine.removeOutputDevice(index)

                            background: Rectangle {
                                color: parent.hovered ? "#9a4a4a" : "#8a3a3a"
                                border.color: "#aa5a5a"
                                radius: 2
                            }

                            contentItem: Label {
                                text: parent.text
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Math.min(11, window.height * 0.018)
                            }
                        }
                    }
                }
            }
        }
    }
}
