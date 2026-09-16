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
// state (the log drain budget, the dispatch index) while sharing the window's
// properties — two engines pretending to be one. The views therefore call the
// functions below instead of reaching into Engine directly.
ApplicationWindow {
    id: window

    width: 1100
    height: 700
    minimumWidth: 900
    minimumHeight: 560
    visible: true
    title: "Spatial Protocol Mapper"

    // Category kept as-is: renaming it would silently orphan every existing
    // user's saved devices.
    Settings {
        id: appSettings
        category: "OSCRouter"

        property bool logReceivedMessages: true
        property bool logSentMessages: false
        property int monitorMaxRate: 500 // max log lines per second displayed
        property int lastViewIndex: 0

        // v2: the whole routing matrix. v1's listenPort + savedOutputDevices
        // are read once by Engine.migrateFromV1() and then left alone.
        property string savedConfiguration: ""
        property int listenPort: 18032
        property string savedOutputDevices: "[]"
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

    readonly property var outputProtocols: ["SpatGRIS", "ADM-OSC", "SPAT Revolution"]
    readonly property var inputProtocols: ["Auto", "SpatGRIS", "ADM-OSC"]
    property alias settings: appSettings

    // ---- Engine state -------------------------------------------------- //
    // Free variables in Engine.js resolve against this object's context.
    // Plain arrays: the engine mutates them, the list models below are what
    // the views bind to.
    property var inputs: []
    property var outputs: []
    property var routes: []

    property alias inputListModel: inputListModel
    property alias outputListModel: outputListModel
    property alias routeListModel: routeListModel
    property alias matrixModel: matrixModel

    ListModel { id: inputListModel }
    ListModel { id: outputListModel }
    // One row per output, describing the current input's route to it.
    ListModel { id: routeListModel }
    // inputs x outputs, row-major, for the matrix grid.
    ListModel { id: matrixModel }

    // Non-empty when two enabled routes write the same source index on some
    // output; shown as a banner under the matrix.
    property string collisionSummary: ""

    property alias messageMonitor: monitorView.messageMonitor

    // Formatting a log line costs more than the routing itself, so it is only
    // done while the monitor is on screen.
    readonly property bool monitorActive: currentViewIndex === monitorViewIndex

    // ---- Current input -------------------------------------------------- //
    // The basic view edits one input at a time. These mirror it as bindable
    // properties, because the engine's state is plain JS with no notifiers.
    property int currentInputId: -1
    property int currentInputIndex: 0
    property string currentInputName: ""
    property string currentInputProtocol: "Auto"
    property int currentInputPort: 18032
    property bool currentInputEnabled: true
    property bool currentInputListening: false
    property string currentInputError: ""
    property string outputError: ""
    // Reported by the input row; a failed addInput() must not surface down in
    // the outputs section.
    property string inputActionError: ""

    function syncCurrentInput() {
        if (currentInputId < 0 && inputs.length > 0)
            currentInputId = inputs[0].id;

        const inp = Engine.findInput(currentInputId);
        if (!inp) {
            if (inputs.length > 0) {
                currentInputId = inputs[0].id;
                syncCurrentInput();
            }
            return;
        }
        for (let i = 0; i < inputs.length; i++)
            if (inputs[i].id === currentInputId) { currentInputIndex = i; break; }
        currentInputName = inp.name;
        currentInputProtocol = inp.protocol;
        currentInputPort = inp.port;
        currentInputEnabled = inp.enabled !== false;
        currentInputListening = inp.listening;
        currentInputError = inp.error;
    }

    function selectInput(id) {
        currentInputId = id;
        syncCurrentInput();
        Engine.updateRouteList(currentInputId);
    }

    // Everything that can change what the views show, in one place.
    function refresh() {
        Engine.updateInputList();
        Engine.updateOutputList();
        Engine.updateRouteList(currentInputId);
        Engine.updateMatrixList();
        collisionSummary = buildCollisionSummary();
        syncCurrentInput();
    }

    function buildCollisionSummary() {
        const clashing = [];
        for (let out of outputs) {
            const cov = Engine.outputCoverage(out.id);
            if (cov.collision)
                clashing.push(out.name + " (" + cov.text + ")");
        }
        if (clashing.length === 0)
            return "";
        return "Two or more routes write the same source index on: "
             + clashing.join(", ")
             + ". The later message wins, so one sender will overwrite the other.";
    }

    function inputNameOf(id) {
        const inp = Engine.findInput(id);
        return inp ? inp.name : "";
    }

    function outputNameOf(id) {
        const out = Engine.findOutput(id);
        return out ? out.name : "";
    }

    // ---- Controller facade ---------------------------------------------- //

    function setListenPort(port) {
        Engine.setInputPort(currentInputId, port);
        refresh();
    }

    function setInputProtocol(protocol) {
        Engine.setInputProtocol(currentInputId, protocol);
        refresh();
    }

    function setListening(listening) {
        Engine.setInputListening(currentInputId, listening);
        refresh();
    }

    function setInputName(name) {
        Engine.setInputName(currentInputId, name);
        refresh();
    }

    function selectInputByIndex(index) {
        if (index >= 0 && index < inputs.length)
            selectInput(inputs[index].id);
    }

    // Returns "" on success, or the reason it was refused. With no port, takes
    // the next free one above those in use, so adding an input is one click.
    function addInput(port) {
        let portNum = parseInt(port);
        if (isNaN(portNum)) {
            portNum = 18032;
            for (let i of inputs)
                portNum = Math.max(portNum, i.port);
            portNum += 1;
            while (portNum < 65535 && Engine.portInUse(portNum, -1))
                portNum++;
        }
        if (portNum < 1 || portNum > 65535)
            return "Port must be between 1 and 65535";
        // Two inputs on one port means the second bind fails at the OS level
        // and the app shows a device that never receives anything.
        if (Engine.portInUse(portNum, -1))
            return "Port " + portNum + " is already used by another input";

        const inp = Engine.createInput("Input " + (inputs.length + 1), portNum, "Auto");
        Engine.saveConfiguration();
        selectInput(inp.id);
        refresh();
        return "";
    }

    function removeCurrentInput() {
        // The engine always has somewhere to route from.
        if (inputs.length <= 1)
            return;
        Engine.removeInput(currentInputId);
        currentInputId = inputs.length > 0 ? inputs[0].id : -1;
        refresh();
    }

    // Returns "" on success, or the reason it was refused.
    function addOutput(name, host, port, protocol) {
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

        const dev = Engine.createOutput(name, host, portNum, protocol);
        // Adding an output from a given input's view wires it to that input.
        if (currentInputId >= 0)
            Engine.setRoute(currentInputId, dev.id, { enabled: true });
        Engine.saveConfiguration();
        refresh();
        return "";
    }

    function removeOutput(outputId) {
        Engine.removeOutput(outputId);
        refresh();
    }

    function clearAllOutputs() {
        while (outputs.length > 0)
            Engine.removeOutput(outputs[0].id);
        refresh();
    }

    function setRouteEnabled(outputId, enabled) {
        Engine.setRoute(currentInputId, outputId, { enabled: enabled });
        Engine.saveConfiguration();
        refresh();
    }

    function setRouteOffset(outputId, offset) {
        Engine.setRoute(currentInputId, outputId, { sourceOffset: offset });
        Engine.saveConfiguration();
        refresh();
    }

    // -1 on either bound means "every source".
    function setRouteRange(outputId, min, max) {
        Engine.setRoute(currentInputId, outputId, {
            srcMin: (min < 0) ? null : min,
            srcMax: (max < 0) ? null : max
        });
        Engine.saveConfiguration();
        refresh();
    }

    // ---- Matrix-addressed edits (explicit input, not the selected one) ---- //

    function setRouteEnabledFor(inputId, outputId, enabled) {
        Engine.setRoute(inputId, outputId, { enabled: enabled });
        Engine.saveConfiguration();
        refresh();
    }

    // -1 on either bound means "every source".
    function setRouteFor(inputId, outputId, offset, min, max) {
        Engine.setRoute(inputId, outputId, {
            sourceOffset: offset,
            srcMin: (min < 0) ? null : min,
            srcMax: (max < 0) ? null : max
        });
        Engine.saveConfiguration();
        refresh();
    }

    // Toggling a whole line flips it to whatever it mostly is not, so one
    // click clears a full row and a second click fills it.
    function toggleRow(inputId) {
        let on = 0;
        for (let out of outputs) {
            const r = Engine.findRoute(inputId, out.id);
            if (r && r.enabled) on++;
        }
        Engine.setRowEnabled(inputId, on < outputs.length);
        Engine.saveConfiguration();
        refresh();
    }

    function toggleColumn(outputId) {
        let on = 0;
        for (let inp of inputs) {
            const r = Engine.findRoute(inp.id, outputId);
            if (r && r.enabled) on++;
        }
        Engine.setColumnEnabled(outputId, on < inputs.length);
        Engine.saveConfiguration();
        refresh();
    }

    function clearLog() {
        Engine.clearLogs();
    }

    // ---- Views ----------------------------------------------------------- //
    readonly property int routingViewIndex: 0
    readonly property int matrixViewIndex: 1
    readonly property int monitorViewIndex: 2
    property int currentViewIndex: appSettings.lastViewIndex
    onCurrentViewIndexChanged: appSettings.lastViewIndex = currentViewIndex

    // ---- Lifecycle -------------------------------------------------------- //
    Component.onCompleted: {
        Engine.restoreConfiguration();
        if (inputs.length > 0)
            currentInputId = inputs[0].id;
        refresh();
    }

    Timer {
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
                    text: "EXPERT"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing
                    isActive: window.currentViewIndex === window.matrixViewIndex
                    onClicked: window.currentViewIndex = window.matrixViewIndex
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
            MatrixView { controller: window }
            MonitorView { id: monitorView; controller: window }
        }
    }
}
