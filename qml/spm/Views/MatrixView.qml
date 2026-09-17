import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Every input against every output, as one gridded table. Same model as the
// routing view.
Pane {
    id: root

    required property var controller

    // Wide enough for a name read straight, rather than turned on its side.
    readonly property int cellWidth: 132
    readonly property int cellHeight: 48
    readonly property int rowHeaderWidth: 220
    readonly property int colHeaderHeight: 48

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

            // The frame hugs the table: a matrix of three inputs does not want
            // a border drawn round half a window of nothing. It grows to the
            // space available and scrolls past it.
            Rectangle {
                id: frame
                width: Math.min(parent.width,
                                root.rowHeaderWidth + root.outputCount * root.cellWidth + 2)
                height: Math.min(parent.height,
                                 root.colHeaderHeight + root.inputCount * root.cellHeight + 2)
                color: Theme.backgroundColor
                border.color: Theme.borderColor
                border.width: 1
                radius: Theme.borderRadius
                clip: true
                visible: root.inputCount > 0 && root.outputCount > 0

            Item {
                id: table
                x: 1
                y: 1
                width: frame.width - 2
                height: frame.height - 2

                // ---- corner --------------------------------------------- //
                Rectangle {
                    width: root.rowHeaderWidth
                    height: root.colHeaderHeight
                    color: Theme.backgroundColorTertiary

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Theme.borderColor
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.borderColor
                    }
                }

                // ---- output columns, scrolled with the cells ------------- //
                Item {
                    x: root.rowHeaderWidth
                    y: 0
                    width: table.width - root.rowHeaderWidth
                    height: root.colHeaderHeight
                    clip: true

                    Row {
                        x: -grid.contentX

                        Repeater {
                            model: root.controller.outputListModel

                            Rectangle {
                                required property var model
                                width: root.cellWidth
                                height: root.colHeaderHeight
                                color: Theme.backgroundColorTertiary

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 0

                                    Item { Layout.fillHeight: true }

                                    CustomLabel {
                                        Layout.fillWidth: true
                                        text: model.name
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }

                                    CustomLabel {
                                        Layout.fillWidth: true
                                        text: model.port
                                        color: Theme.textColorSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        elide: Text.ElideRight
                                    }

                                    Item { Layout.fillHeight: true }
                                }

                                ToolTip.visible: headerHover.hovered
                                ToolTip.delay: 400
                                ToolTip.text: model.name + "\n" + model.protocol
                                              + " · " + model.host + ":" + model.port
                                HoverHandler { id: headerHover }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 1
                                    color: Theme.borderColor
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Theme.borderColor
                                }
                            }
                        }
                    }
                }

                // ---- input rows, scrolled with the cells ----------------- //
                Item {
                    x: 0
                    y: root.colHeaderHeight
                    width: root.rowHeaderWidth
                    height: table.height - root.colHeaderHeight
                    clip: true

                    Column {
                        y: -grid.contentY

                        Repeater {
                            model: root.controller.inputListModel

                            Rectangle {
                                required property var model
                                width: root.rowHeaderWidth
                                height: root.cellHeight
                                color: Theme.backgroundColorTertiary

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
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
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeSmall
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    CustomLabel {
                                        text: model.port
                                        color: Theme.textColorSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 1
                                    color: Theme.borderColor
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 1
                                    color: Theme.borderColor
                                }
                            }
                        }
                    }
                }

                // ---- the cells ------------------------------------------- //
                Flickable {
                    id: grid
                    x: root.rowHeaderWidth
                    y: root.colHeaderHeight
                    width: table.width - root.rowHeaderWidth
                    height: table.height - root.colHeaderHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    contentWidth: root.outputCount * root.cellWidth
                    contentHeight: root.inputCount * root.cellHeight

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    Grid {
                        columns: Math.max(1, root.outputCount)
                        spacing: 0

                        Repeater {
                            // Row-major, matching Engine.updateMatrixList().
                            model: root.controller.matrixModel

                            MatrixCell {
                                required property var model

                                width: root.cellWidth
                                height: root.cellHeight
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

            }

            CustomLabel {
                anchors.centerIn: parent
                visible: root.inputCount === 0 || root.outputCount === 0
                color: Theme.textColorSecondary
                text: root.outputCount === 0 ? "No outputs yet." : "No inputs yet."
            }
        }
    }
}
