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
        xField.text = ScaleFormat.number(x);
        yField.text = ScaleFormat.number(y);
        zField.text = ScaleFormat.number(z);
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
        text: root.inputName === "" ? root.title : root.title + " — " + root.inputName
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
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: root.valid ? Theme.textColorSecondary : Theme.errorColor
            text: !root.valid
                  ? "Each factor must be a number between -100 and 100."
                  : "A negative factor mirrors that axis; 1 leaves it alone. "
                    + "Scaling all three alike changes distance without moving "
                    + "anything."
        }
    }

    onOpened: {
        const ok = root.standardButton(Dialog.Ok);
        if (ok)
            ok.enabled = Qt.binding(function () { return root.valid; });
    }
}
