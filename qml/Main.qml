import QtCore
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm
import "spm/Engine.js" as Engine

// Spatial Protocol Mapper — entry point and controller facade.
//
// Engine.js is imported *here only*. It is not a `.pragma library`, so every
// QML file that imports it would otherwise get its own copy of the module
// state (the ADM accumulator, the log drain budget) while sharing the window's
// properties — two engines pretending to be one. The views therefore call the
// functions below instead of reaching into Engine directly, which also leaves
// a single seam to swap the engine behind when routing moves to a matrix.
ApplicationWindow {
    id: window

    width: 1100
    height: 700
    minimumWidth: 900
    minimumHeight: 560
    visible: true
    title: "Spatial Protocol Mapper"

    // Category kept as-is: renaming it would silently orphan every existing
    // user's saved output devices.
    Settings {
        id: appSettings
        category: "OSCRouter"

        property int listenPort: 18032
        property bool logReceivedMessages: true
        property bool logSentMessages: false
        property int monitorMaxRate: 500 // max log lines per second displayed
        property string savedOutputDevices: "[]"
        property int lastViewIndex: 0
    }

    // Dark unless the OS explicitly asks for light (Unknown reads as dark).
    Binding {
        target: Theme
        property: "dark"
        value: Application.styleHints.colorScheme !== Qt.ColorScheme.Light
    }

    palette {
        text: Theme.textColor
        windowText: Theme.textColor
        buttonText: Theme.textColor
        brightText: Theme.textColorOnAccent
        placeholderText: Theme.textColorSecondary

        window: Theme.backgroundColor
        base: Theme.backgroundColorSecondary
        alternateBase: Theme.backgroundColorTertiary

        light: Theme.backgroundColorSecondary
        midlight: Theme.backgroundColorTertiary
        mid: Theme.borderColor
        dark: Theme.borderColor
        shadow: Theme.backgroundColor

        button: Theme.buttonBgInactive
        highlight: Theme.primaryColor
        highlightedText: Theme.textColorOnAccent

        link: Theme.primaryColor
        linkVisited: Theme.secondaryColor
    }

    color: Theme.backgroundColor

    // Exposed to the views, which are given this window as their `controller`
    // rather than reaching into its ids through the QML context chain.
    property alias settings: appSettings
    readonly property var outputProtocols: ["SpatGRIS", "ADM-OSC", "SPAT Revolution"]

    // ---- Engine state ------------------------------------------------- //
    // Free variables in Engine.js resolve against this object's context.
    property var outputDevices: []
    property var oscInput
    property var udpInput
    property string inputPortError: ""
    property bool inputListening: false
    property string outputError: ""

    // Owned here rather than by a view: the list outlives any one tab, and
    // Engine.updateOutputList() writes into it.
    property alias outputListModel: outputListModel
    ListModel { id: outputListModel }

    property alias messageMonitor: monitorView.messageMonitor

    // Formatting a log line costs more than the routing itself, so it is only
    // done while the monitor is on screen — the same trade the collapsible
    // log pane used to make, now keyed on the tab instead of its visibility.
    readonly property bool monitorActive: currentViewIndex === monitorViewIndex

    // ---- Views -------------------------------------------------------- //
    readonly property int routingViewIndex: 0
    readonly property int monitorViewIndex: 1
    property int currentViewIndex: appSettings.lastViewIndex
    onCurrentViewIndexChanged: appSettings.lastViewIndex = currentViewIndex

    // ---- Controller facade -------------------------------------------- //
    // Everything the views are allowed to ask the engine to do.

    function setListenPort(port) {
        Engine.closeInputDevice();
        appSettings.listenPort = port;
    }

    function startListening() {
        Engine.createInputDevice(appSettings.listenPort);
    }

    function stopListening() {
        Engine.closeInputDevice();
    }

    // Returns "" on success, or the reason it was refused.
    function addOutput(name, host, port, type) {
        name = (name || "").trim();
        host = (host || "").trim();
        const portNum = parseInt(port);

        if (!name)
            return "Name is required";
        if (!host)
            return "Host is required";
        if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(host) && !/^[a-zA-Z0-9][a-zA-Z0-9.\-]*$/.test(host))
            return "Invalid host address";
        if (isNaN(portNum) || portNum < 1 || portNum > 65535)
            return "Port must be between 1 and 65535";

        Engine.createOutputDevice(name, host, portNum, type);
        return "";
    }

    function removeOutput(index) {
        Engine.removeOutputDevice(index);
    }

    function setOutputActive(index, active) {
        if (index < 0 || index >= outputDevices.length)
            return;
        outputDevices[index].active = active;
        Engine.updateOutputList();
        Engine.saveOutputDevices();
    }

    function setOutputOffset(index, offset) {
        if (index < 0 || index >= outputDevices.length)
            return;
        outputDevices[index].sourceIndexOffset = offset;
        Engine.saveOutputDevices();
    }

    function clearAllOutputs() {
        while (outputDevices.length > 0)
            Engine.removeOutputDevice(0);
    }

    function clearLog() {
        Engine.clearLogs();
    }

    // ---- Lifecycle ----------------------------------------------------- //
    Component.onCompleted: {
        Engine.restoreSavedSettings();
        Engine.createInputDevice(appSettings.listenPort);
    }

    Timer {
        id: logFlushTimer
        interval: 16
        running: window.monitorActive
        repeat: true
        onTriggered: Engine.flushLogs()
    }

    AboutDialog {
        id: aboutDialog
        parentWindow: window
        appName: "Spatial Protocol Mapper"
        appDescription: "A tool developed by the Société des Arts Technologiques"
        appDetails: "Route and translate spatial audio positioning between "
                    + "SpatGRIS, ADM-OSC and SPAT Revolution over OSC."
        appWebsite: "https://github.com/sat-mtl/spatial-protocol-mapper"
        // Relative paths would resolve against AboutDialog.qml in the submodule.
        logoPath: Qt.resolvedUrl("spm/resources/images/logo.png")
        partnerLogos: [
            { source: Qt.resolvedUrl("spm/resources/images/sat_logo.png"), website: "https://www.sat.qc.ca" },
            { source: Qt.resolvedUrl("spm/resources/images/ossia_logo.png"), website: "https://ossia.io" }
        ]
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: sidebar
            width: Theme.sidebarWidth
            Layout.fillHeight: true
            color: Theme.sidebarBackgroundColor

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Theme.padding
                anchors.bottomMargin: Theme.padding
                spacing: Theme.spacing

                Image {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 60
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.padding
                    source: "spm/resources/images/logo.png"
                    fillMode: Image.PreserveAspectFit

                    MouseArea {
                        anchors.fill: parent
                        onClicked: aboutDialog.open()
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                CustomButton {
                    text: "BASIC"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing
                    isActive: window.currentViewIndex === window.routingViewIndex
                    onClicked: window.currentViewIndex = window.routingViewIndex
                }

                CustomButton {
                    text: "MONITOR"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing
                    isActive: window.currentViewIndex === window.monitorViewIndex
                    onClicked: window.currentViewIndex = window.monitorViewIndex
                }

                Item { Layout.fillHeight: true }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: window.currentViewIndex

            RoutingView { controller: window }
            MonitorView { id: monitorView; controller: window }
        }
    }
}
