import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Protocol handlers: the bundled ones, user scripts on disk, and inline
// scripts written in the editor here. See docs/HANDLERS.md for writing one.
Pane {
    id: root

    required property var controller

    // The editor replaces the list while a script is open.
    property bool editing: false

    function openEditor(url, name) {
        root.controller.handlerScriptSource(url, function (source, error) {
            editor.load(url, name, source, error);
            root.editing = true;
        });
    }

    padding: 0
    background: Rectangle { color: Theme.backgroundColor }

    FileDialog {
        id: scriptDialog
        title: "Add a handler script"
        nameFilters: ["JavaScript (*.js)", "All files (*)"]
        onAccepted: root.controller.addHandlerScript(selectedFile.toString())
    }

    ScriptEditor {
        id: editor
        anchors.fill: parent
        anchors.margins: Theme.padding
        visible: root.editing

        onApplyRequested: text => root.controller.applyHandlerScript(
                              editor.url, text, function (result) {
                                  editor.applied(result, text);
                                  editor.title = root.controller.handlerScriptName(editor.url);
                              })
        onCloseRequested: root.editing = false
    }

    ColumnLayout {
        visible: !root.editing
        anchors.fill: parent
        anchors.margins: Theme.padding
        spacing: Theme.spacing

        SectionHeader { text: "Protocol handlers" }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.backgroundColor
            border.color: Theme.borderColor
            border.width: 1
            radius: Theme.borderRadius
            clip: true

            ListView {
                id: handlerList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: root.controller.handlerListModel

                delegate: Rectangle {
                    id: row
                    required property var model

                    width: ListView.view ? ListView.view.width : 0
                    implicitHeight: 48
                    color: Theme.backgroundColorSecondary

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.separatorColor
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacing * 2
                        anchors.rightMargin: Theme.spacing * 2
                        spacing: Theme.spacing

                        CustomLabel {
                            Layout.preferredWidth: 200
                            text: row.model.name
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        CustomLabel {
                            Layout.preferredWidth: 70
                            text: row.model.directions
                            color: Theme.textColorSecondary
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        CustomLabel {
                            Layout.fillWidth: true
                            text: row.model.error !== "" ? row.model.error
                                  : row.model.builtin ? "Built-in"
                                  : row.model.inline ? "Stored in the app" : row.model.url
                            color: row.model.error !== "" ? Theme.errorColor : Theme.textColorSecondary
                            font.pixelSize: Theme.fontSizeSmall
                            elide: row.model.error !== "" ? Text.ElideRight : Text.ElideLeft

                            ToolTip.visible: !row.model.builtin && textHover.hovered
                            ToolTip.text: row.model.error !== ""
                                          ? row.model.url + "\n" + row.model.error : row.model.url
                            HoverHandler { id: textHover }
                        }

                        RowButton {
                            Layout.preferredWidth: Columns.action
                            visible: !row.model.builtin
                            text: "Edit"
                            onClicked: root.openEditor(row.model.url, row.model.name)
                        }

                        RowButton {
                            Layout.preferredWidth: Columns.action
                            // An inline script has no file to re-read.
                            visible: !row.model.builtin && !row.model.inline
                            text: "Reload"
                            onClicked: root.controller.reloadHandlerScript(row.model.url)
                        }

                        RowButton {
                            Layout.preferredWidth: Columns.action
                            visible: !row.model.builtin
                            text: "Remove"
                            onClicked: root.controller.removeHandlerScript(row.model.url)
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
                text: "+ New script"
                onClicked: {
                    const url = root.controller.newHandlerScript();
                    root.openEditor(url, root.controller.handlerScriptName(url));
                }
            }

            CustomButton {
                Layout.preferredWidth: 130
                height: Theme.buttonHeight
                text: "+ Open file"
                onClicked: scriptDialog.open()
            }

            CustomButton {
                Layout.preferredWidth: 110
                height: Theme.buttonHeight
                text: "Reload all"
                onClicked: root.controller.reloadHandlerScripts()
            }

            CustomLabel {
                Layout.fillWidth: true
                text: "Devices on a script's protocol pick up changes on reload."
                color: Theme.textColorSecondary
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }
    }
}
