import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Per-route source-id range editor. Shared by the basic view's output rows and
// (later) the matrix cells, so a range means the same thing wherever it is set.
//
// The filter tests the *incoming* source index, before the route's offset is
// applied — the numbers here are the ones on the sender, not on the receiver.
//
// -1 on either bound means unbounded; `rangeAccepted` reports the same.
Dialog {
    id: root

    property string routeLabel: ""
    property int srcMin: -1
    property int srcMax: -1

    signal rangeAccepted(int min, int max)

    title: "Source range"
    modal: true
    standardButtons: Dialog.Ok | Dialog.Cancel
    closePolicy: Popup.CloseOnEscape

    // Refusing is better than silently forwarding nothing: a route that can
    // never match is indistinguishable from a broken one at the wire.
    readonly property bool rangeValid: allSources.checked
                                       || minBox.value <= maxBox.value

    function editRoute(label, min, max) {
        routeLabel = label;
        allSources.checked = (min < 0 && max < 0);
        minBox.value = (min < 0) ? 1 : min;
        maxBox.value = (max < 0) ? 128 : max;
        open();
    }

    onAccepted: {
        if (allSources.checked)
            rangeAccepted(-1, -1);
        else
            rangeAccepted(minBox.value, maxBox.value);
    }

    background: Rectangle {
        color: Theme.backgroundColorSecondary
        border.color: Theme.borderColor
        border.width: 1
        radius: Theme.borderRadius
    }

    header: CustomLabel {
        text: root.routeLabel === "" ? root.title : root.title + " — " + root.routeLabel
        font.bold: true
        font.pixelSize: Theme.fontSizeSubtitle
        padding: Theme.padding
        elide: Text.ElideRight
    }

    ColumnLayout {
        spacing: Theme.spacing

        CustomSwitch {
            id: allSources
            text: "Forward every source"
            checked: true
        }

        GridLayout {
            columns: 2
            columnSpacing: Theme.spacing
            rowSpacing: Theme.spacing
            enabled: !allSources.checked
            opacity: enabled ? 1.0 : 0.4

            CustomLabel { text: "From source" }
            CustomSpinBox {
                id: minBox
                Layout.preferredWidth: 150
                from: 1
                to: 9999
                value: 1
            }

            CustomLabel { text: "To source" }
            CustomSpinBox {
                id: maxBox
                Layout.preferredWidth: 150
                from: 1
                to: 9999
                value: 128
            }
        }

        CustomLabel {
            Layout.preferredWidth: 300
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: root.rangeValid ? Theme.textColorSecondary : Theme.errorColor
            text: !root.rangeValid
                  ? "The first source must not be greater than the last."
                  : allSources.checked
                    ? "Every source on this input reaches this output."
                    : "Sources outside this range are dropped for this output only. "
                      + "The range is matched before the offset is applied."
        }
    }

    // Keep OK unavailable rather than accepting a range that matches nothing.
    onOpened: okButton().enabled = Qt.binding(function () { return root.rangeValid; })
    function okButton() { return root.standardButton(Dialog.Ok); }
}
