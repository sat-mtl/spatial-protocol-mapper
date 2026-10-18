import QtCore
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import ca.qc.sat.qmlcomponents
import spm
import "spm/Engine.js" as Engine

// Entry point and controller facade.
//
// Engine.js is imported here only: it is not a `.pragma library`, so a second
// importer would get its own copy of the module state. The views call the
// functions below instead.
ApplicationWindow {
    id: window

    width: 1100
    height: 700
    // The view's own margins, plus the 1px frame each table draws.
    minimumWidth: Theme.sidebarWidth + 2 * Theme.padding + 2 + Columns.minimumRowWidth
    minimumHeight: 560
    visible: true
    title: "Spatial Protocol Mapper"

    // Renaming the category orphans every existing user's saved devices.
    Settings {
        id: appSettings
        category: "OSCRouter"

        property bool logReceivedMessages: true
        property bool logSentMessages: false
        property int monitorMaxRate: 500 // max log lines per second displayed
        property int lastViewIndex: 0

        // v1's listenPort and savedOutputDevices are read once by
        // Engine.migrateFromV1() and then left alone.
        property string savedConfiguration: ""
        property int listenPort: 18032
        property string savedOutputDevices: "[]"

        // URLs of user handler scripts (file:// or inline:), as a JSON array.
        property string handlerScripts: "[]"
        // Sources of the inline scripts written in the editor, by URL.
        property string inlineScripts: "{}"

        onLogReceivedMessagesChanged: Engine.updateLogging()
        onLogSentMessagesChanged: Engine.updateLogging()
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

    // Protocol pickers list ids and names in parallel: handlers are picked by
    // id and shown by name. Rebuilt by refresh(), since scripts come and go.
    property var inputProtocolIds: []
    property var inputProtocolNames: []
    property var outputProtocolIds: []
    property var outputProtocolNames: []
    property var builtinOutputChoices: []
    property var scriptedOutputChoices: []
    property alias settings: appSettings

    // ---- Engine state -------------------------------------------------- //
    // Free variables in Engine.js resolve against this object's context. The
    // engine mutates these; the views bind to the list models below.
    property var inputs: []
    property var outputs: []
    property var routes: []

    property alias inputListModel: inputListModel
    property alias outputListModel: outputListModel
    property alias routeListModel: routeListModel
    property alias matrixModel: matrixModel
    property alias handlerListModel: handlerListModel

    ListModel { id: inputListModel }
    ListModel { id: outputListModel }
    // One row per output, describing the current input's route to it.
    ListModel { id: routeListModel }
    // inputs x outputs, row-major, for the matrix grid.
    ListModel { id: matrixModel }
    // Bundled handlers and user scripts, for the scripts view.
    ListModel { id: handlerListModel }

    property alias messageMonitor: monitorView.messageMonitor

    // Formatting a log line costs more than the routing, so it is gated.
    readonly property bool monitorActive: currentViewIndex === monitorViewIndex
    onMonitorActiveChanged: Engine.updateLogging()

    // ---- Current input -------------------------------------------------- //
    // Bindable mirrors: the engine's state is plain JS with no notifiers.
    property int currentInputId: -1
    property int currentInputIndex: 0
    property string currentInputName: ""
    property string currentInputProtocol: "Auto"
    property int currentInputPort: 18032
    property bool currentInputEnabled: true
    property bool currentInputListening: false
    property string currentInputError: ""
    // Reported by the input row.
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

    function refresh() {
        const ins = Engine.protocolOptions("input");
        inputProtocolIds = ins.ids;
        inputProtocolNames = ins.names;
        const outs = Engine.protocolOptions("output");
        outputProtocolIds = outs.ids;
        outputProtocolNames = outs.names;
        builtinOutputChoices = Engine.outputChoices(true);
        scriptedOutputChoices = Engine.outputChoices(false);

        Engine.updateInputList();
        Engine.updateOutputList();
        Engine.updateRouteList(currentInputId);
        Engine.updateMatrixList();
        syncCurrentInput();
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

    function updateInput(inputId, props) {
        Engine.updateInput(inputId, props);
        refresh();
    }

    function setInputListening(inputId, listening) {
        Engine.setInputListening(inputId, listening);
        refresh();
    }

    function updateOutput(outputId, props) {
        Engine.updateOutput(outputId, props);
        refresh();
    }

    // Returns "" on success, or the reason it was refused. With no port, takes
    // the next free one above those in use.
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
        // Two inputs on one port: the second bind fails at the OS level.
        if (Engine.portInUse(portNum, -1))
            return "Port " + portNum + " is already used by another input";

        const inp = Engine.createInput("Input " + (inputs.length + 1), portNum, "Auto");
        Engine.saveConfiguration();
        selectInput(inp.id);
        refresh();
        return "";
    }

    function removeInput(inputId) {
        if (inputs.length <= 1)
            return;
        Engine.removeInput(inputId);
        if (currentInputId === inputId)
            currentInputId = inputs.length > 0 ? inputs[0].id : -1;
        refresh();
    }

    // Adds a ready-to-edit output for that protocol, on its usual port.
    function addOutput(protocol) {
        let n = 1;
        for (let o of outputs)
            if (o.protocol === protocol) n++;

        const dev = Engine.createOutput(Engine.protocolName(protocol) + " " + n, "127.0.0.1",
                                        Engine.defaultPortFor(protocol), protocol);
        if (currentInputId >= 0)
            Engine.setRoute(currentInputId, dev.id, { enabled: true });
        Engine.saveConfiguration();
        refresh();
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

    function clearLog() {
        Engine.clearLogs();
    }

    // ---- Handler settings and scripts ------------------------------------- //

    function deviceOf(kind, id) {
        return kind === "input" ? Engine.findInput(id) : Engine.findOutput(id);
    }

    // { specs, values } for the params dialog.
    function deviceParams(kind, id) {
        const dev = deviceOf(kind, id);
        if (!dev) return { specs: [], values: {} };
        return { specs: Engine.paramSpecs(dev.protocol), values: Engine.paramValues(dev) };
    }

    function setDeviceParams(kind, id, values) {
        const dev = deviceOf(kind, id);
        if (!dev) return;
        Engine.setDeviceParams(dev, values, kind);
        Engine.saveConfiguration();
        refresh();
    }

    function addHandlerScript(url) {
        Engine.addScript(url, function () { refresh(); });
    }

    function reloadHandlerScript(url) {
        Engine.reloadScript(url);
    }

    function reloadHandlerScripts() {
        Engine.reloadScripts();
    }

    // A new script stored in the settings, from the template. Returns its URL.
    function newHandlerScript() {
        const url = Engine.newInlineScript();
        refresh();
        return url;
    }

    function handlerScriptName(url) {
        return Engine.scriptName(url);
    }

    // `done(source, error)`.
    function handlerScriptSource(url, done) {
        Engine.readSource(url, done);
    }

    // Saves and loads the script; `done({ error, line, saved, running })`.
    function applyHandlerScript(url, source, done) {
        Engine.applyScript(url, source, function (result) {
            refresh();
            done(result);
        });
    }

    function removeHandlerScript(url) {
        Engine.removeScript(url);
        refresh();
    }

    // ---- Views ----------------------------------------------------------- //
    readonly property int routingViewIndex: 0
    readonly property int matrixViewIndex: 1
    readonly property int monitorViewIndex: 2
    readonly property int handlersViewIndex: 3
    property int currentViewIndex: appSettings.lastViewIndex
    onCurrentViewIndexChanged: appSettings.lastViewIndex = currentViewIndex

    // ---- Lifecycle -------------------------------------------------------- //
    Component.onCompleted: {
        Engine.updateLogging();
        Engine.restoreConfiguration();
        // Asynchronous: devices on a scripted protocol pick it up on arrival.
        Engine.loadSavedScripts();
        Engine.updateHandlerList();
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
                    + "SpatGRIS, ADM-OSC, SPAT Revolution and scripted protocols over OSC."
        appWebsite: "https://github.com/sat-mtl/spatial-protocol-mapper"
        // Relative paths would resolve against AboutDialog.qml in the submodule.
        logoPath: Qt.resolvedUrl("spm/resources/images/logo.png")
        partnerLogos: [
            { source: Theme.satLogoSource, website: "https://www.sat.qc.ca" },
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
                    text: "MATRIX"
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

                CustomButton {
                    text: "SCRIPTS"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing
                    isActive: window.currentViewIndex === window.handlersViewIndex
                    onClicked: window.currentViewIndex = window.handlersViewIndex
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
            HandlersView { controller: window }
        }
    }
}
