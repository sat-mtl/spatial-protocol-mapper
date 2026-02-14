import QtCore
import QtQuick.Controls.Universal
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Score.UI as UI
import "./Engine.js" as Engine

ApplicationWindow {
    id: window
    visible: true
    width: 800
    height: 600
    title: "OSC Spatialization Router"
    color: "#1e1e1e"

    Settings {
        id: appSettings
        category: "OSCRouter"

        property int listenPort: 18032
        property bool logReceivedMessages: true
        property bool logSentMessages: true
        property bool monitorVisible: true
        property string savedOutputDevices: "[]"
    }

    property var inputDevice: null
    property var outputDevices: []
    property var addressMappings: new Map()
    property var oscInput
    property var udpInput

    property alias messageMonitor: console_section.messageMonitor
    property alias inputPortField: input_section.inputPortField
    property alias outputListModel: output_section.outputListModel

    Component.onCompleted: {
        Engine.restoreSavedSettings();

        Engine.createInputDevice(appSettings.listenPort);
    }

    header: Item {
        width: 1
        height: 5
    }

    menuBar: TopMenu {}

    SplitView {
        Layout.margins: 10
        anchors.fill: parent
        orientation: Qt.Vertical

        handle: Rectangle {
            implicitHeight: 6
            color: SplitHandle.pressed ? "#5a5a5a" : SplitHandle.hovered ? "#4a4a4a" : "#3a3a3a"

            Rectangle {
                width: 40
                height: 2
                radius: 1
                color: "#6a6a6a"
                anchors.centerIn: parent
            }
        }

        InputSection {
            id: input_section
        }
        OutputSection {
            id: output_section
        }
        ConsoleSection {
            id: console_section
        }
    }
}
