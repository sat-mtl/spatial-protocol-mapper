import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm

// Per-route editor: source range and index offset. Shared by the basic view's
// output rows and the matrix cells, so a route means the same thing wherever
// it is set.
//
// The range tests the *incoming* source index, before the offset is applied —
// the numbers here are the ones on the sender, not on the receiver.
//
// -1 on either bound means unbounded; `routeEdited` reports the same.
Dialog {
    id: root

    property string routeLabel: ""

    signal routeEdited(int offset, int min, int max)

    title: "Route"
    modal: true
    standardButtons: Dialog.Ok | Dialog.Cancel
    closePolicy: Popup.CloseOnEscape

    // Refusing is better than silently forwarding nothing: a route that can
    // never match looks exactly like a broken one at the wire.
    readonly property bool rangeValid: allSources.checked || minBox.value <= maxBox.value

    function editRoute(label, offset, min, max) {
        routeLabel = label;
        offsetBox.value = offset;
        allSources.checked = (min < 0 && max < 0);
        minBox.value = (min < 0) ? 1 : min;
        maxBox.value = (max < 0) ? 128 : max;
        open();
    }

    onAccepted: {
        if (allSources.checked)
            routeEdited(offsetBox.value, -1, -1);
        else
            routeEdited(offsetBox.value, minBox.value, maxBox.value);
    }

    background: Rectangle {
        color: Theme.backgroundColorSecondary
        border.color: Theme.borderColor
        border.width: 1
        radius: Theme.borderRadius
    }

    header: CustomLabel {
        text: root.routeLabel === "" ? root.title : root.routeLabel
        font.bold: true
        font.pixelSize: Theme.fontSizeSubtitle
        padding: Theme.padding
        elide: Text.ElideRight
    }

    ColumnLayout {
        spacing: Theme.spacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing

            CustomLabel { text: "Source offset" }
            Item { Layout.fillWidth: true }
            CustomSpinBox {
                id: offsetBox
                Layout.preferredWidth: 150
                from: 0
                to: 9999
                value: 0
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.separatorColor
        }

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
            Layout.preferredWidth: 320
            visible: !root.rangeValid
            color: Theme.errorColor
            font.pixelSize: Theme.fontSizeSmall
            text: "Invalid range"
        }
    }

    // Keep OK unavailable rather than accepting a range that matches nothing.
    onOpened: {
        const ok = root.standardButton(Dialog.Ok);
        if (ok)
            ok.enabled = Qt.binding(function () { return root.rangeValid; });
    }
}
