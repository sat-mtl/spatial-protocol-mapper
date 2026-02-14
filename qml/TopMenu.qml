import QtCore
import QtQuick.Controls.Universal
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Score.UI as UI
import "./Engine.js" as Engine

RowLayout {

    spacing: 10

    Label {
        text: "Quick Setup:"
        color: "#ffffff"
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Math.min(12, window.height * 0.02)
    }

    Button {
        Layout.preferredWidth: Math.max(80, Math.min(120, window.width * 0.12))
        text: "SpatGRIS"
        onClicked: Engine.createOutputDevice("SpatGRIS_1", "127.0.0.1", 18042, "SpatGRIS")

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

    Button {
        Layout.preferredWidth: Math.max(80, Math.min(120, window.width * 0.12))
        text: "ADM-OSC"
        onClicked: Engine.createOutputDevice("ADM_1", "127.0.0.1", 9000, "ADM-OSC")

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

    Button {
        Layout.preferredWidth: Math.max(80, Math.min(120, window.width * 0.12))
        text: "SPAT Rev"
        onClicked: Engine.createOutputDevice("SPAT_1", "127.0.0.1", 8088, "SPAT Revolution")

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

    Button {
        Layout.preferredWidth: Math.max(70, Math.min(100, window.width * 0.1))
        text: appSettings.monitorVisible ? "Hide Log" : "Show Log"

        onClicked: appSettings.monitorVisible = !appSettings.monitorVisible

        background: Rectangle {
            color: appSettings.monitorVisible ? (parent.hovered ? "#5a8a5a" : "#4a7a4a") : (parent.hovered ? "#5a5a5a" : "#4a4a4a")
            border.color: appSettings.monitorVisible ? "#6aaa6a" : "#6a6a6a"
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

    Button {
        Layout.preferredWidth: Math.max(70, Math.min(100, window.width * 0.1))
        text: "Clear All"

        onClicked: {
            while (outputDevices.length > 0) {
                Engine.removeOutputDevice(0);
            }
        }

        background: Rectangle {
            color: parent.hovered ? "#9a4a4a" : "#8a3a3a"
            border.color: "#aa5a5a"
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
}
