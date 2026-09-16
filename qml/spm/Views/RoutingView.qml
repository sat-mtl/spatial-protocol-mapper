import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Basic mode: one input, every output fed from it.
Pane {
    id: root

    // The application window, acting as the controller facade.
    required property var controller

    padding: 0
    background: Rectangle { color: Theme.backgroundColor }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacing

        CustomLabel {
            text: "Basic routing"
            font.bold: true
            font.pixelSize: Theme.fontSizeTitle
        }

        // ---- Input ---------------------------------------------------- //

        SectionHeader {
            text: "Input"
            hint: "positions received from ControlGRIS or an ADM-OSC sender"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            CustomLabel { text: "Listen port" }

            CustomTextField {
                id: listenPortField
                Layout.preferredWidth: 110
                text: root.controller.settings.listenPort
                color: acceptableInput ? Theme.textColor : Theme.errorColor
                validator: IntValidator { bottom: 1; top: 65535 }
                onTextEdited: {
                    if (acceptableInput)
                        root.controller.setListenPort(parseInt(text));
                }
            }

            CustomSwitch {
                text: "Listen"
                checked: root.controller.inputListening
                onToggled: {
                    if (checked)
                        root.controller.startListening();
                    else
                        root.controller.stopListening();
                }
            }

            CustomLabel {
                text: root.controller.inputPortError
                visible: root.controller.inputPortError !== ""
                color: Theme.errorColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: root.controller.inputPortError === "" }
        }

        // ---- Outputs -------------------------------------------------- //

        SectionHeader {
            text: "Outputs"
            hint: "every active output receives every incoming source"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            CustomLabel {
                text: "Quick setup"
                color: Theme.textColorSecondary
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: [
                    { label: "SpatGRIS", name: "SpatGRIS_1", host: "127.0.0.1", port: 18042, type: "SpatGRIS" },
                    { label: "ADM-OSC", name: "ADM_1", host: "127.0.0.1", port: 9000, type: "ADM-OSC" },
                    { label: "SPAT Rev", name: "SPAT_1", host: "127.0.0.1", port: 8088, type: "SPAT Revolution" }
                ]

                CustomButton {
                    required property var modelData
                    Layout.preferredWidth: 110
                    height: Theme.buttonHeight
                    text: modelData.label
                    onClicked: root.controller.addOutput(modelData.name, modelData.host,
                                                        modelData.port, modelData.type)
                }
            }

            Item { Layout.fillWidth: true }

            CustomButton {
                Layout.preferredWidth: 110
                height: Theme.buttonHeight
                text: "Remove all"
                enabled: root.controller.outputListModel.count > 0
                opacity: enabled ? 1.0 : 0.4
                onClicked: root.controller.clearAllOutputs()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            CustomTextField {
                id: nameField
                Layout.preferredWidth: 160
                placeholderText: "Name"
                onTextChanged: root.controller.outputError = ""
            }

            CustomTextField {
                id: hostField
                Layout.preferredWidth: 160
                text: "127.0.0.1"
                placeholderText: "IP address"
                onTextChanged: root.controller.outputError = ""
            }

            CustomTextField {
                id: portField
                Layout.preferredWidth: 110
                text: "8000"
                placeholderText: "Port"
                color: acceptableInput ? Theme.textColor : Theme.errorColor
                validator: IntValidator { bottom: 1; top: 65535 }
                onTextChanged: root.controller.outputError = ""
            }

            CustomComboBox {
                id: protocolCombo
                Layout.preferredWidth: 180
                model: root.controller.outputProtocols
            }

            AccentButton {
                Layout.preferredWidth: 90
                text: "Add"
                onClicked: {
                    const err = root.controller.addOutput(nameField.text, hostField.text,
                                                          portField.text, protocolCombo.currentText);
                    root.controller.outputError = err;
                    if (err === "") {
                        nameField.clear();
                        portField.text = "8000";
                    }
                }
            }

            CustomLabel {
                text: root.controller.outputError
                visible: root.controller.outputError !== ""
                color: Theme.errorColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: root.controller.outputError === "" }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ScrollView {
                anchors.fill: parent
                clip: true

                ListView {
                    model: root.controller.outputListModel
                    spacing: 6

                    delegate: OutputRow {
                        required property int index
                        required property var model

                        width: ListView.view ? ListView.view.width : 0
                        name: model.name
                        host: model.host
                        port: model.port
                        protocol: model.type
                        active: model.active
                        sourceOffset: model.sourceIndexOffset

                        onActiveToggled: value => root.controller.setOutputActive(index, value)
                        onOffsetEdited: value => root.controller.setOutputOffset(index, value)
                        onRemoveRequested: root.controller.removeOutput(index)
                    }
                }
            }

            CustomLabel {
                anchors.centerIn: parent
                visible: root.controller.outputListModel.count === 0
                color: Theme.textColorSecondary
                text: "No outputs yet — use Quick setup above, or fill in the form."
            }
        }
    }
}
