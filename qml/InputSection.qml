import QtCore
import QtQuick.Controls.Universal
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Score.UI as UI
import "./Engine.js" as Engine

GroupBox {
    property alias inputPortField: inputPortField
    SplitView.fillWidth: true
    SplitView.fillHeight: false
    SplitView.minimumHeight: 100
    SplitView.preferredHeight: 100
    title: "Input Configuration (from ControlGRIS)"
    topPadding: label.height

    background: Rectangle {
        color: "#2a2a2a"
        border.color: "#3a3a3a"
        radius: 4
    }

    label: Label {
        text: parent.title
        color: "#ffffff"
        font.bold: true
        font.pointSize: skin.fontLarge
        padding: 5
    }

    RowLayout {
        anchors.top: parent.top
        anchors.left: parent.left

        Label {
            text: "Listen Port:"
            color: "#ffffff"
            verticalAlignment: Text.AlignVCenter
            font.pointSize: skin.fontMedium
        }

        TextField {
            id: inputPortField
            Layout.preferredWidth: 80
            text: "18032"
            color: acceptableInput ? "#fff" : "#f00"
            font.pointSize: skin.fontMedium

            background: Rectangle {
                color: "#3a3a3a"
                border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                radius: 2
            }
            validator: IntValidator {
                bottom: 1
                top: 65535
            }
            onTextChanged: appSettings.listenPort = inputPortField.text
        }

        CheckBox {
            id: listenCheckBox
            text: "Listen"
            checked: inputListening
            onToggled: {
                if (checked) {
                    Engine.createInputDevice(parseInt(inputPortField.text));
                } else {
                    Engine.closeInputDevice();
                }
            }

            contentItem: Label {
                text: parent.text
                color: "#ffffff"
                leftPadding: parent.indicator.width + parent.spacing
                verticalAlignment: Text.AlignVCenter
                font.pointSize: skin.fontMedium
            }
        }

        Label {
            text: inputPortError
            color: "#ff4444"
            visible: inputPortError !== ""
            font.pointSize: skin.fontMedium
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
