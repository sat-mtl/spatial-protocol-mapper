import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Plain-text editor for a handler script: line numbers, the failing line
// highlighted, Tab and Enter that keep the indentation, Ctrl+S to apply.
Item {
    id: root

    property string url: ""
    property string title: ""
    // What is stored; the text differs from it while there are unsaved edits.
    property string savedText: ""
    readonly property bool dirty: edit.text !== savedText

    property string status: ""
    property bool statusIsError: false
    // 1-based line the last error points at, or -1.
    property int errorLine: -1

    // Close asks once before discarding edits.
    property bool confirmingClose: false

    readonly property string monoFont: "IBM Plex Mono"
    readonly property string indentUnit: "    "

    signal applyRequested(string text)
    signal closeRequested

    function load(scriptUrl, scriptTitle, text, error) {
        url = scriptUrl;
        title = scriptTitle;
        savedText = text;
        edit.text = text;
        edit.cursorPosition = 0;
        flick.contentY = 0;
        confirmingClose = false;
        errorLine = -1;
        status = error;
        statusIsError = error !== "";
        edit.forceActiveFocus();
    }

    // The result of applying `text`: { error, line, saved, running }.
    function applied(result, text) {
        if (result.saved) savedText = text;
        errorLine = result.line;
        statusIsError = result.error !== "";
        if (result.error === "")
            status = "Applied.";
        else if (!result.saved)
            status = "Not saved: " + result.error;
        else
            status = result.error + (result.running ? " — saved, not applied; the previous version keeps running"
                                                    : " — saved, not applied");
        if (errorLine > 0) showLine(errorLine);
    }

    function showLine(line) {
        const y = (line - 1) * lineHeight;
        if (y < flick.contentY || y + lineHeight > flick.contentY + flick.height)
            flick.contentY = Math.max(0, y - flick.height / 3);
    }

    readonly property real lineHeight: edit.lineCount > 0 ? edit.contentHeight / edit.lineCount : 16

    Shortcut {
        sequences: [StandardKey.Save]
        enabled: root.visible
        onActivated: root.applyRequested(edit.text)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            CustomLabel {
                text: root.title + (root.dirty ? " •" : "")
                font.bold: true
                font.pixelSize: Theme.fontSizeSubtitle
                elide: Text.ElideRight
                Layout.maximumWidth: 260
            }

            CustomLabel {
                Layout.fillWidth: true
                text: root.status
                color: root.statusIsError ? Theme.errorColor : Theme.textColorSecondary
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight

                ToolTip.visible: root.status !== "" && statusHover.hovered
                ToolTip.text: root.status
                HoverHandler { id: statusHover }
            }

            CustomButton {
                Layout.preferredWidth: 90
                height: Theme.buttonHeight
                text: "Apply"
                onClicked: root.applyRequested(edit.text)

                ToolTip.visible: applyHover.hovered
                ToolTip.delay: 400
                ToolTip.text: "Save and load the script (Ctrl+S)"
                HoverHandler { id: applyHover }
            }

            CustomButton {
                Layout.preferredWidth: 90
                height: Theme.buttonHeight
                text: "Revert"
                enabled: root.dirty
                opacity: enabled ? 1.0 : 0.4
                onClicked: {
                    edit.text = root.savedText;
                    root.confirmingClose = false;
                }
            }

            CustomButton {
                Layout.preferredWidth: 130
                height: Theme.buttonHeight
                text: root.confirmingClose ? "Discard edits?" : "Close"
                onClicked: {
                    if (root.dirty && !root.confirmingClose) {
                        root.confirmingClose = true;
                        return;
                    }
                    root.confirmingClose = false;
                    root.closeRequested();
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.backgroundColorSecondary
            border.color: edit.activeFocus ? Theme.primaryColor : Theme.borderColor
            border.width: 1
            radius: Theme.borderRadius
            clip: true

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 1
                contentWidth: Math.max(width, gutter.width + edit.contentWidth + 2 * Theme.spacing)
                contentHeight: Math.max(height, edit.y + edit.contentHeight + Theme.spacing)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ScrollBar.vertical: ScrollBar {}
                ScrollBar.horizontal: ScrollBar {}

                // Keeps the cursor in view while typing.
                function ensureVisible(r) {
                    const x = r.x + edit.x, y = r.y + edit.y;
                    if (contentX >= x) contentX = Math.max(0, x - gutter.width);
                    else if (contentX + width <= x + r.width) contentX = x + r.width - width + Theme.spacing;
                    if (contentY >= y) contentY = y;
                    else if (contentY + height <= y + r.height) contentY = y + r.height - height + Theme.spacing;
                }

                Rectangle {
                    visible: root.errorLine > 0 && root.errorLine <= edit.lineCount
                    x: 0
                    y: edit.y + (root.errorLine - 1) * root.lineHeight
                    width: flick.contentWidth
                    height: root.lineHeight
                    color: Theme.errorColor
                    opacity: 0.18
                }

                Text {
                    id: gutter
                    x: 0
                    y: edit.y
                    width: Math.max(32, implicitWidth) + Theme.spacing
                    rightPadding: Theme.spacing
                    horizontalAlignment: Text.AlignRight
                    font.family: root.monoFont
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textColorSecondary
                    text: {
                        let s = "";
                        for (let i = 1; i <= edit.lineCount; i++) s += (i > 1 ? "\n" : "") + i;
                        return s;
                    }
                    lineHeight: root.lineHeight
                    lineHeightMode: Text.FixedHeight
                }

                TextEdit {
                    id: edit
                    x: gutter.width + Theme.spacing
                    y: Theme.spacing
                    width: Math.max(implicitWidth, flick.width - x)
                    // Fills the view, so a click below the last line lands here.
                    height: Math.max(implicitHeight, flick.height - y)
                    font.family: root.monoFont
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.textColor
                    selectionColor: Theme.primaryColor
                    selectedTextColor: Theme.textColorOnAccent
                    selectByMouse: true
                    persistentSelection: true
                    wrapMode: TextEdit.NoWrap
                    textFormat: TextEdit.PlainText
                    onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                    onTextChanged: if (root.confirmingClose && !root.dirty) root.confirmingClose = false

                    // The indentation of the line the cursor is on.
                    function currentIndent() {
                        const start = text.lastIndexOf("\n", cursorPosition - 1) + 1;
                        let end = start;
                        while (end < text.length && (text[end] === " " || text[end] === "\t")) end++;
                        return text.substring(start, Math.min(end, cursorPosition));
                    }

                    Keys.onTabPressed: event => {
                        if (selectedText !== "") remove(selectionStart, selectionEnd);
                        insert(cursorPosition, root.indentUnit);
                        event.accepted = true;
                    }
                    // A new line keeps the indentation, one level deeper after { or [.
                    function newLine(event) {
                        if (selectedText !== "") remove(selectionStart, selectionEnd);
                        const indent = currentIndent();
                        const before = cursorPosition > 0 ? text[cursorPosition - 1] : "";
                        insert(cursorPosition, "\n" + indent + ((before === "{" || before === "[") ? root.indentUnit : ""));
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: event => newLine(event)
                    Keys.onEnterPressed: event => newLine(event)
                }
            }
        }
    }
}
