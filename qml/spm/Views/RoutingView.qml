import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Two tables with the same columns: the inputs, and the outputs the selected
// input feeds.
Pane {
    id: root

    required property var controller

    padding: 0
    background: Rectangle { color: Theme.backgroundColor }

    InputScaleDialog {
        id: scaleDialog
        parent: Overlay.overlay
        anchors.centerIn: parent

        property int inputId: -1
        onScaleAccepted: (x, y, z) => root.controller.updateInput(
                             inputId, { scaleX: x, scaleY: y, scaleZ: z })
    }

    RouteEditDialog {
        id: routeDialog
        parent: Overlay.overlay
        anchors.centerIn: parent

        property int outputId: -1
        onRouteEdited: (offset, min, max) => root.controller.setRouteFor(
                           root.controller.currentInputId, outputId, offset, min, max)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacing

        // ---- Inputs ---------------------------------------------------- //

        SectionHeader { text: "Inputs" }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: inputHeader.height + inputList.contentHeight + 2
            Layout.maximumHeight: inputHeader.height + 4 * 48 + 2
            color: Theme.backgroundColor
            border.color: Theme.borderColor
            border.width: 1
            radius: Theme.borderRadius
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                TableHeader {
                    id: inputHeader
                    Layout.fillWidth: true
                    hostTitle: "Address"
                    routeTitle: "Scale"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderColor
                }

                ListView {
                    id: inputList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    interactive: contentHeight > height
                    model: root.controller.inputListModel

                    delegate: InputRow {
                        required property var model

                        width: ListView.view ? ListView.view.width : 0
                        name: model.name
                        port: model.port
                        protocol: model.protocol
                        listening: model.enabled
                        error: model.error
                        protocols: root.controller.inputProtocols
                        scaleX: model.scaleX
                        scaleY: model.scaleY
                        scaleZ: model.scaleZ
                        // Only worth marking once there is more than one.
                        selected: model.inputId === root.controller.currentInputId
                                  && root.controller.inputListModel.count > 1

                        onSelectRequested: root.controller.selectInput(model.inputId)
                        onListeningToggled: value => root.controller.setInputListening(model.inputId, value)
                        onNameEdited: value => root.controller.updateInput(model.inputId, { name: value })
                        onPortEdited: value => root.controller.updateInput(model.inputId, { port: value })
                        onProtocolEdited: value => root.controller.updateInput(model.inputId, { protocol: value })
                        onRemoveRequested: root.controller.removeInput(model.inputId)
                        onScaleEditRequested: {
                            scaleDialog.inputId = model.inputId;
                            scaleDialog.editScale(model.name, model.scaleX,
                                                  model.scaleY, model.scaleZ);
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            CustomButton {
                Layout.preferredWidth: 130
                height: Theme.buttonHeight
                text: "+ Input"
                onClicked: root.controller.inputActionError = root.controller.addInput()
            }

            CustomLabel {
                text: root.controller.inputActionError
                visible: root.controller.inputActionError !== ""
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item { Layout.fillWidth: root.controller.inputActionError === "" }
        }

        // ---- Outputs --------------------------------------------------- //

        SectionHeader { text: "Outputs" }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.backgroundColor
            border.color: Theme.borderColor
            border.width: 1
            radius: Theme.borderRadius
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                TableHeader {
                    Layout.fillWidth: true
                    hostTitle: "Address"
                    routeTitle: "Sources"
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderColor
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: root.controller.routeListModel

                    delegate: OutputRow {
                        required property var model

                        width: ListView.view ? ListView.view.width : 0
                        name: model.name
                        host: model.host
                        port: model.port
                        protocol: model.protocol
                        protocols: root.controller.outputProtocols
                        routed: model.routed
                        sourceOffset: model.sourceOffset
                        srcMin: model.srcMin
                        srcMax: model.srcMax
                        alsoFedBy: model.alsoFedBy

                        onRoutedToggled: value => root.controller.setRouteEnabled(model.outputId, value)
                        onNameEdited: value => root.controller.updateOutput(model.outputId, { name: value })
                        onHostEdited: value => root.controller.updateOutput(model.outputId, { host: value })
                        onPortEdited: value => root.controller.updateOutput(model.outputId, { port: value })
                        onProtocolEdited: value => root.controller.updateOutput(model.outputId, { protocol: value })
                        onRemoveRequested: root.controller.removeOutput(model.outputId)
                        onRouteEditRequested: {
                            routeDialog.outputId = model.outputId;
                            routeDialog.editRoute(
                                root.controller.currentInputName + "  →  " + model.name,
                                model.sourceOffset, model.srcMin, model.srcMax);
                        }
                    }
                }
            }

            CustomLabel {
                anchors.centerIn: parent
                visible: root.controller.routeListModel.count === 0
                color: Theme.textColorSecondary
                text: "No outputs yet."
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            Repeater {
                model: root.controller.outputProtocols

                CustomButton {
                    required property var modelData
                    Layout.preferredWidth: 160
                    height: Theme.buttonHeight
                    text: "+ " + modelData
                    onClicked: root.controller.addOutput(modelData)
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
    }
}
