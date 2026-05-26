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
    title: "Spatial Protocol Mapper"
    color: "#1e1e1e"
    font: style.fontSans
    property alias skin: style

    Settings {
        id: appSettings
        category: "OSCRouter"

        property int listenPort: 18032
        property bool logReceivedMessages: true
        property bool logSentMessages: false
        property bool monitorVisible: false
        property int monitorMaxRate: 500 // max log lines per second displayed
        property string savedOutputDevices: "[]"
    }

    Style {
        id: style
    }

    property var inputDevice: null
    property var outputDevices: []
    property var addressMappings: new Map()
    property var oscInput
    property var udpInput
    property string inputPortError: ""
    property bool inputListening: false
    property string outputError: ""

    property alias messageMonitor: console_section.messageMonitor
    property alias inputPortField: input_section.inputPortField
    property alias outputListModel: output_section.outputListModel

    Component.onCompleted: {
        Engine.restoreSavedSettings();

        Engine.createInputDevice(appSettings.listenPort);
    }

    Timer {
        id: logFlushTimer
        interval: 16
        running: appSettings.monitorVisible
        repeat: true
        onTriggered: Engine.flushLogs()
    }

    function clearLog() {
        Engine.clearLogs();
    }

    header: Item {
        width: 1
        height: 5
    }

    menuBar: TopMenu {

    }

    SplitView {
        // Layout.margins: 10
        // padding: 5
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
