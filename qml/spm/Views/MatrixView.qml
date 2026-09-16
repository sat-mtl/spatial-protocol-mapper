import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Expert mode: every input against every output, at once.
//
// Same model as the basic view, different presentation — this one exists to
// show the whole system together, which is the only place the per-output
// coverage and collision warnings mean anything.
Pane {
    id: root

    required property var controller

    readonly property int cellSize: 46
    readonly property int cellGap: 4
    readonly property int rowHeaderWidth: 190
    readonly property int colHeaderHeight: 104
    // Length of the turned column label; its vertical extent is this times
    // sin(60°), which has to stay inside colHeaderHeight minus the toggle.
    readonly property int labelLength: 92

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

        CustomLabel {
            text: "Routing matrix"
            font.bold: true
            font.pixelSize: Theme.fontSizeTitle
        }

        SectionHeader {
            text: "Connections"
            hint: "click to connect · right-click for offset and source range"
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.inputCount > 0 && root.outputCount > 0

            // ---- corner ------------------------------------------------ //
            CustomLabel {
                x: 0
                y: 0
                width: root.rowHeaderWidth
                height: root.colHeaderHeight
                verticalAlignment: Text.AlignBottom
                text: "inputs ↓ / outputs →"
                color: Theme.textColorSecondary
                font.pixelSize: Theme.fontSizeSmall
                bottomPadding: 6
            }

            // ---- column headers, scrolled horizontally with the body ---- //
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
                            clip: false

                            // Names are far longer than a cell is wide; turning
                            // them keeps the column readable without widening
                            // the grid. Rotated about its own left edge so the
                            // text runs up and to the right from the cell.
                            CustomLabel {
                                x: root.cellSize / 2
                                y: root.colHeaderHeight - 26
                                width: root.labelLength
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: model.collision ? Theme.errorColor : Theme.textColor
                                text: model.name
                                transform: Rotation { angle: -60; origin.x: 0; origin.y: 0 }
                            }

                            ToolTip.visible: headerHover.hovered
                            ToolTip.delay: 300
                            ToolTip.text: model.name + "\n" + model.protocol + " · "
                                          + model.host + ":" + model.port + "\n"
                                          + (model.feederCount === 0
                                             ? "nothing routed here"
                                             : "receives " + model.coverage)
                                          + (model.collision
                                             ? "\n⚠ two routes write the same source index"
                                             : "")
                            HoverHandler { id: headerHover }

                            // Mute or unmute this destination in one click.
                            CustomButton {
                                id: toggle
                                anchors.bottom: parent.bottom
                                width: root.cellSize
                                height: 22
                                text: "⇕"
                                onClicked: root.controller.toggleColumn(model.outputId)

                                ToolTip.visible: colToggleHover.hovered
                                ToolTip.delay: 400
                                ToolTip.text: "Connect or mute every input for " + model.name
                                HoverHandler { id: colToggleHover }
                            }
                        }
                    }
                }
            }

            // ---- row headers, scrolled vertically with the body --------- //
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
                                spacing: 6

                                // Bound and receiving, bound and idle, or off.
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: !model.enabled ? Theme.borderColor
                                         : model.error !== "" ? Theme.errorColor
                                                              : Theme.buttonBgActive
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    CustomLabel {
                                        text: model.name
                                        font.bold: true
                                        font.pixelSize: Theme.fontSizeSmall
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    CustomLabel {
                                        text: ":" + model.port + " · " + model.protocol
                                        color: Theme.textColorSecondary
                                        font.pixelSize: Theme.fontSizeSmall
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }

                                CustomButton {
                                    Layout.preferredWidth: 32
                                    height: 22
                                    text: "⇔"
                                    onClicked: root.controller.toggleRow(model.inputId)

                                    ToolTip.visible: rowToggleHover.hovered
                                    ToolTip.delay: 400
                                    ToolTip.text: "Connect or mute every output for " + model.name
                                    HoverHandler { id: rowToggleHover }
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
            wrapMode: Text.WordWrap
            text: root.outputCount === 0
                  ? "Add an output in BASIC before routing anything."
                  : "Add an input in BASIC before routing anything."
        }

        // ---- collisions ------------------------------------------------ //
        // Splitting one sender across outputs by source id is exactly what
        // makes two routes land on the same index; say so rather than letting
        // it be discovered by ear.
        Rectangle {
            Layout.fillWidth: true
            visible: collisionText.text !== ""
            implicitHeight: collisionText.implicitHeight + 2 * Theme.spacing
            color: Qt.rgba(Theme.errorColor.r, Theme.errorColor.g, Theme.errorColor.b, 0.15)
            border.color: Theme.errorColor
            border.width: 1
            radius: Theme.borderRadius

            CustomLabel {
                id: collisionText
                anchors.fill: parent
                anchors.margins: Theme.spacing
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                text: root.controller.collisionSummary
            }
        }
    }
}
