import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Basic mode: one input at a time, and the outputs it feeds.
Pane {
    id: root

    // The application window, acting as the controller facade.
    required property var controller

    padding: 0
    background: Rectangle { color: Theme.backgroundColor }

    RouteRangeDialog {
        id: rangeDialog
        parent: Overlay.overlay
        anchors.centerIn: parent

        property int outputId: -1
        onRangeAccepted: (min, max) => root.controller.setRouteRange(outputId, min, max)
    }

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
                Layout.preferredWidth: 110
                text: root.controller.currentInputPort
                color: acceptableInput ? Theme.textColor : Theme.errorColor
                validator: IntValidator { bottom: 1; top: 65535 }
                onTextEdited: {
                    if (acceptableInput)
                        root.controller.setListenPort(parseInt(text));
                }
            }

            CustomLabel { text: "Protocol" }

            CustomComboBox {
                Layout.preferredWidth: 150
                model: root.controller.inputProtocols
                currentIndex: Math.max(0, model.indexOf(root.controller.currentInputProtocol))
                onActivated: root.controller.setInputProtocol(currentText)
            }

            CustomSwitch {
                text: "Listen"
                checked: root.controller.currentInputEnabled
                onToggled: root.controller.setListening(checked)
            }

            CustomLabel {
                text: root.controller.currentInputError
                visible: root.controller.currentInputError !== ""
                color: Theme.errorColor
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: root.controller.currentInputError === "" }
        }

        // ---- Outputs -------------------------------------------------- //

        SectionHeader {
            text: "Outputs"
            hint: "each switch is this input's route to that output"
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
                enabled: root.controller.routeListModel.count > 0
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
                    model: root.controller.routeListModel
                    spacing: 6

                    delegate: OutputRow {
                        required property var model

                        width: ListView.view ? ListView.view.width : 0
                        name: model.name
                        host: model.host
                        port: model.port
                        protocol: model.protocol
                        routed: model.routed
                        sourceOffset: model.sourceOffset
                        srcMin: model.srcMin
                        srcMax: model.srcMax
                        alsoFedBy: model.alsoFedBy

                        onRoutedToggled: value => root.controller.setRouteEnabled(model.outputId, value)
                        onOffsetEdited: value => root.controller.setRouteOffset(model.outputId, value)
                        onRemoveRequested: root.controller.removeOutput(model.outputId)
                        onRangeEditRequested: {
                            rangeDialog.outputId = model.outputId;
                            rangeDialog.editRoute(model.name, model.srcMin, model.srcMax);
                        }
                    }
                }
            }

            CustomLabel {
                anchors.centerIn: parent
                visible: root.controller.routeListModel.count === 0
                color: Theme.textColorSecondary
                text: "No outputs yet — use Quick setup above, or fill in the form."
            }
        }
    }
}
