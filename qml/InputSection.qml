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

    background: Rectangle {
        color: "#2a2a2a"
        border.color: "#3a3a3a"
        radius: 4
    }

    label: Label {
        text: parent.title
        color: "#ffffff"
        font.bold: true
        font.pixelSize: Math.min(14, window.height * 0.025)
        padding: 5
    }

    RowLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: 10

        Label {
            text: "Listen Port:"
            color: "#ffffff"
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Math.min(12, window.height * 0.02)
        }

        TextField {
            id: inputPortField
            Layout.preferredWidth: Math.min(80, window.width * 0.1)
            text: "18032"
            color: acceptableInput ? "#fff" : "#f00"
            font.pixelSize: Math.min(12, window.height * 0.02)

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

        Button {
            text: "Apply"
            Layout.preferredWidth: Math.min(80, window.width * 0.1)
            onClicked: Engine.createInputDevice(parseInt(inputPortField.text))

            background: Rectangle {
                color: parent.hovered ? "#5a5a5a" : "#4a4a4a"
                border.color: "#6a6a6a"
                radius: 2
            }

            contentItem: Label {
                text: parent.text
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Math.min(12, window.height * 0.02)
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
