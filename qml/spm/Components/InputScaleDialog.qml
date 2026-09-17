import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Per-input axis scaling: corrects a sender whose room is a different size, or
// whose axes are mirrored relative to ours.
//
// Applies to every message from that input, before any route sees it.
Dialog {
    id: root

    property string inputName: ""

    signal scaleAccepted(real x, real y, real z)

    title: "Scale"
    modal: true
    standardButtons: Dialog.Ok | Dialog.Cancel
    closePolicy: Popup.CloseOnEscape

    readonly property bool valid: xField.acceptableInput
                                  && yField.acceptableInput
                                  && zField.acceptableInput

    function editScale(name, x, y, z) {
        inputName = name;
        xField.text = Format.number(x);
        yField.text = Format.number(y);
        zField.text = Format.number(z);
        open();
    }

    onAccepted: scaleAccepted(parseFloat(xField.text),
                              parseFloat(yField.text),
                              parseFloat(zField.text))

    background: Rectangle {
        color: Theme.backgroundColorSecondary
        border.color: Theme.borderColor
        border.width: 1
        radius: Theme.borderRadius
    }

    header: CustomLabel {
        text: root.inputName === "" ? root.title : root.title + ": " + root.inputName
        font.bold: true
        font.pixelSize: Theme.fontSizeSubtitle
        padding: Theme.padding
        elide: Text.ElideRight
    }

    ColumnLayout {
        spacing: Theme.spacing

        component AxisField: CustomTextField {
            Layout.preferredWidth: 130
            horizontalAlignment: Text.AlignHCenter
            color: acceptableInput ? Theme.textColor : Theme.errorColor
            validator: DoubleValidator {
                bottom: -100.0
                top: 100.0
                decimals: 4
                notation: DoubleValidator.StandardNotation
            }
        }

        GridLayout {
            columns: 2
            columnSpacing: Theme.spacing
            rowSpacing: Theme.spacing

            CustomLabel { text: "Left / right" }
            AxisField { id: xField }

            CustomLabel { text: "Back / front" }
            AxisField { id: yField }

            CustomLabel { text: "Down / up" }
            AxisField { id: zField }
        }

        CustomButton {
            Layout.preferredWidth: 130
            height: Theme.buttonHeight
            text: "Reset"
            onClicked: { xField.text = "1"; yField.text = "1"; zField.text = "1"; }
        }

        CustomLabel {
            Layout.preferredWidth: 330
            visible: !root.valid
            color: Theme.errorColor
            font.pixelSize: Theme.fontSizeSmall
            text: "Invalid factor"
        }
    }

    onOpened: {
        const ok = root.standardButton(Dialog.Ok);
        if (ok)
            ok.enabled = Qt.binding(function () { return root.valid; });
    }
}
