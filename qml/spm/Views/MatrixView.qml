import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Every input against every output. Same model as the routing view.
Pane {
    id: root

    required property var controller

    readonly property int cellSize: 46
    readonly property int cellGap: 4
    readonly property int rowHeaderWidth: 200
    readonly property int colHeaderHeight: 150

    readonly property int inputCount: controller.inputListModel.count
    readonly property int outputCount: controller.outputListModel.count

    padding: 0
    background: Rectangle { color: Theme.backgroundColor }

    RouteEditDialog {
        id: routeDialog
        parent: Overlay.overlay
        anchors.centerIn: parent

        property int inputId: -1
        property int outputId: -1
        onRouteEdited: (offset, min, max) =>
            root.controller.setRouteFor(inputId, outputId, offset, min, max)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacing

        SectionHeader { text: "Connections" }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.inputCount > 0 && root.outputCount > 0

            // ---- column headers, scrolled with the cells ---------------- //
            Item {
                x: root.rowHeaderWidth
                y: 0
                width: parent.width - root.rowHeaderWidth
                height: root.colHeaderHeight
                clip: true

                Row {
                    x: -grid.contentX
                    spacing: root.cellGap

                    Repeater {
                        model: root.controller.outputListModel

                        Item {
                            required property var model
                            width: root.cellSize
                            height: root.colHeaderHeight

                            // Turned a quarter rather than squeezed: the names
                            // are far wider than a cell and elision left them
                            // unreadable. Rotated about its own top-left, so
                            // the text runs up from the bottom of the header.
                            CustomLabel {
                                x: (root.cellSize - height) / 2
                                y: root.colHeaderHeight - 8
                                width: root.colHeaderHeight - 20
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeBody
                                text: model.name
                                transform: Rotation { angle: -90; origin.x: 0; origin.y: 0 }
                            }

                            ToolTip.visible: headerHover.hovered
                            ToolTip.delay: 400
                            ToolTip.text: model.name + "\n" + model.protocol
                                          + " · " + model.host + ":" + model.port
                            HoverHandler { id: headerHover }
                        }
                    }
                }
            }

            // ---- row headers, scrolled with the cells ------------------- //
            Item {
                x: 0
                y: root.colHeaderHeight
                width: root.rowHeaderWidth
                height: parent.height - root.colHeaderHeight
                clip: true

                Column {
                    y: -grid.contentY
                    spacing: root.cellGap

                    Repeater {
                        model: root.controller.inputListModel

                        Item {
                            required property var model
                            width: root.rowHeaderWidth
                            height: root.cellSize

                            RowLayout {
                                anchors.fill: parent
                                anchors.rightMargin: Theme.spacing
                                spacing: 8

                                // Listening, or switched off.
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: model.enabled ? Theme.buttonBgActive
                                                         : Theme.borderColor
                                }

                                CustomLabel {
                                    text: model.name
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                CustomLabel {
                                    text: model.port
                                    color: Theme.textColorSecondary
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }
            }

            // ---- the cells --------------------------------------------- //
            Flickable {
                id: grid
                x: root.rowHeaderWidth
                y: root.colHeaderHeight
                width: parent.width - root.rowHeaderWidth
                height: parent.height - root.colHeaderHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                contentWidth: root.outputCount * (root.cellSize + root.cellGap)
                contentHeight: root.inputCount * (root.cellSize + root.cellGap)

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                Grid {
                    columns: Math.max(1, root.outputCount)
                    spacing: root.cellGap

                    Repeater {
                        // Row-major, matching Engine.updateMatrixList().
                        model: root.controller.matrixModel

                        MatrixCell {
                            required property var model

                            width: root.cellSize
                            height: root.cellSize
                            routed: model.routed
                            sourceOffset: model.sourceOffset
                            srcMin: model.srcMin
                            srcMax: model.srcMax
                            inputName: root.controller.inputNameOf(model.inputId)
                            outputName: root.controller.outputNameOf(model.outputId)

                            onToggled: root.controller.setRouteEnabledFor(
                                           model.inputId, model.outputId, !model.routed)
                            onEditRequested: {
                                routeDialog.inputId = model.inputId;
                                routeDialog.outputId = model.outputId;
                                routeDialog.editRoute(
                                    inputName + "  →  " + outputName,
                                    model.sourceOffset, model.srcMin, model.srcMax);
                            }
                        }
                    }
                }
            }
        }

        CustomLabel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.inputCount === 0 || root.outputCount === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Theme.textColorSecondary
            text: root.outputCount === 0 ? "No outputs yet." : "No inputs yet."
        }
    }
}
