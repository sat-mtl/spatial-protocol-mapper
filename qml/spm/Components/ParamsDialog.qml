import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// A device's handler settings, built from the params its handler declares:
//   [{ key, label?, type: "int"|"real"|"bool"|"string"|"enum", min?, max?, options? }]
Dialog {
    id: root

    property string deviceName: ""
    property var specs: []
    property var values: ({})

    signal paramsAccepted(var values)

    title: "Settings"
    modal: true
    standardButtons: Dialog.Ok | Dialog.Cancel
    closePolicy: Popup.CloseOnEscape

    function editParams(name, paramSpecs, current) {
        deviceName = name;
        values = current;
        specs = paramSpecs;
        open();
    }

    readonly property bool valid: {
        for (let i = 0; i < fields.count; i++) {
            const f = fields.itemAt(i);
            if (f && !f.acceptable) return false;
        }
        return true;
    }

    onAccepted: {
        const out = {};
        for (let i = 0; i < fields.count; i++) {
            const f = fields.itemAt(i);
            if (f) out[f.spec.key] = f.value();
        }
        paramsAccepted(out);
    }

    background: Rectangle {
        color: Theme.backgroundColorSecondary
        border.color: Theme.borderColor
        border.width: 1
        radius: Theme.borderRadius
    }

    header: CustomLabel {
        text: root.deviceName === "" ? root.title : root.title + ": " + root.deviceName
        font.bold: true
        font.pixelSize: Theme.fontSizeSubtitle
        padding: Theme.padding
        elide: Text.ElideRight
    }

    GridLayout {
        columns: 2
        columnSpacing: Theme.spacing
        rowSpacing: Theme.spacing

        Repeater {
            id: fields
            model: root.specs

            // One row: the label and whichever editor the type calls for.
            delegate: RowLayout {
                id: field
                required property var modelData
                readonly property var spec: modelData
                readonly property var current: root.values[spec.key]
                readonly property bool numeric: spec.type === "int" || spec.type === "real"
                readonly property bool acceptable: !numeric || text.acceptableInput

                Layout.columnSpan: 2
                spacing: Theme.spacing

                function value() {
                    switch (spec.type) {
                    case "int": return parseInt(text.text);
                    case "real": return parseFloat(text.text);
                    case "bool": return toggle.checked;
                    case "enum": return spec.options[choice.currentIndex];
                    }
                    return text.text;
                }

                CustomLabel {
                    Layout.preferredWidth: 160
                    text: field.spec.label || field.spec.key
                    elide: Text.ElideRight
                }

                CustomTextField {
                    id: text
                    visible: field.spec.type === "int" || field.spec.type === "real"
                             || field.spec.type === "string"
                    Layout.preferredWidth: 180
                    text: field.current === undefined ? "" : String(field.current)
                    color: acceptableInput ? Theme.textColor : Theme.errorColor
                    validator: field.spec.type === "int" ? intValidator
                             : field.spec.type === "real" ? realValidator : null

                    IntValidator {
                        id: intValidator
                        bottom: typeof field.spec.min === "number" ? field.spec.min : -2147483647
                        top: typeof field.spec.max === "number" ? field.spec.max : 2147483647
                    }
                    DoubleValidator {
                        id: realValidator
                        bottom: typeof field.spec.min === "number" ? field.spec.min : -1e12
                        top: typeof field.spec.max === "number" ? field.spec.max : 1e12
                        notation: DoubleValidator.StandardNotation
                    }
                }

                CustomSwitch {
                    id: toggle
                    visible: field.spec.type === "bool"
                    checked: field.current === true
                }

                CustomComboBox {
                    id: choice
                    visible: field.spec.type === "enum"
                    Layout.preferredWidth: 180
                    model: field.spec.type === "enum" ? field.spec.options : []
                    currentIndex: field.spec.type === "enum"
                                  ? Math.max(0, field.spec.options.indexOf(field.current)) : -1
                }
            }
        }

        CustomLabel {
            Layout.columnSpan: 2
            visible: root.specs.length === 0
            color: Theme.textColorSecondary
            text: "This handler has no settings."
        }
    }

    onOpened: {
        const ok = root.standardButton(Dialog.Ok);
        if (ok)
            ok.enabled = Qt.binding(function () { return root.valid; });
    }
}
