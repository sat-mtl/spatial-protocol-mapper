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

    ParamsDialog {
        id: paramsDialog
        parent: Overlay.overlay
        anchors.centerIn: parent

        property string kind: ""
        property int deviceId: -1
        onParamsAccepted: values => root.controller.setDeviceParams(kind, deviceId, values)
    }

    function editParams(kind, id, name) {
        paramsDialog.kind = kind;
        paramsDialog.deviceId = id;
        const p = root.controller.deviceParams(kind, id);
        paramsDialog.editParams(name, p.specs, p.values);
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
            Layout.preferredHeight: inputHeader.height + 1 + inputList.contentHeight + 2
            Layout.maximumHeight: inputHeader.height + 1 + 4 * 48 + 2
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
                        protocolIds: root.controller.inputProtocolIds
                        protocolNames: root.controller.inputProtocolNames
                        hasParams: model.hasParams
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
                        onParamsEditRequested: root.editParams("input", model.inputId, model.name)
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
                        protocolIds: root.controller.outputProtocolIds
                        protocolNames: root.controller.outputProtocolNames
                        hasParams: model.hasParams
                        error: model.error
                        routed: model.routed
                        sourceOffset: model.sourceOffset
                        srcMin: model.srcMin
                        srcMax: model.srcMax

                        onRoutedToggled: value => root.controller.setRouteEnabled(model.outputId, value)
                        onNameEdited: value => root.controller.updateOutput(model.outputId, { name: value })
                        onHostEdited: value => root.controller.updateOutput(model.outputId, { host: value })
                        onPortEdited: value => root.controller.updateOutput(model.outputId, { port: value })
                        onProtocolEdited: value => root.controller.updateOutput(model.outputId, { protocol: value })
                        onRemoveRequested: root.controller.removeOutput(model.outputId)
                        onParamsEditRequested: root.editParams("output", model.outputId, model.name)
                        onRouteEditRequested: {
                            routeDialog.outputId = model.outputId;
                            routeDialog.editRoute(
                                root.controller.currentInputName + " to " + model.name,
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

            // Bundled protocols get a button each; scripted ones share a menu.
            Repeater {
                model: root.controller.builtinOutputChoices

                CustomButton {
                    required property var modelData
                    Layout.preferredWidth: 160
                    height: Theme.buttonHeight
                    text: "+ " + modelData.name
                    onClicked: root.controller.addOutput(modelData.id)
                }
            }

            CustomButton {
                id: scriptedButton
                Layout.preferredWidth: 160
                height: Theme.buttonHeight
                visible: root.controller.scriptedOutputChoices.length > 0
                text: "+ Scripted…"
                onClicked: scriptedMenu.popup(scriptedButton, 0, scriptedButton.height)

                Menu {
                    id: scriptedMenu
                    Repeater {
                        model: root.controller.scriptedOutputChoices
                        MenuItem {
                            required property var modelData
                            text: modelData.name
                            onTriggered: root.controller.addOutput(modelData.id)
                        }
                    }
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
