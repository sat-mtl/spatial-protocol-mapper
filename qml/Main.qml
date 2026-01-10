import QtQuick 
import QtQuick.Layouts 
import QtQuick.Controls 2.15
import Score.UI as UI

ApplicationWindow {
    id: window
    visible: true
    width: 800
    height: 600
    title: "OSC Spatialization Router"
    color: "#1e1e1e"

    property var inputDevice: null
    property var outputDevices: []
    property var addressMappings: new Map()
    property var oscInput
    property var udpInput

    // Input configuration
    Component.onCompleted: {
        // Create input device for receiving from ControlGRIS
        createInputDevice()
    }

    function createInputDevice() {
        udpInput = null;
        oscInput = null;
        oscInput = Protocols.osc({ onOsc:function (a,v) { onInputValueReceived(a,v);} });
        udpInput = Protocols.inboundUDP({
                                          Transport: { Bind: "0.0.0.0", Port: parseInt(inputPortField.text) }
                                        , onMessage: function(bytes) { oscInput.processMessage(bytes); }
                                       });
    }

    function onInputValueReceived(address, value) {
        messageMonitor.append(`IN: ${address} = ${JSON.stringify(value)}`)
        // Update monitor
        if (messageMonitor.lineCount > 15) {
            messageMonitor.remove(0, messageMonitor.text.indexOf('\n') + 1)
        }
        
        // Only process /spat/serv messages from ControlGRIS
        
        if (address !== "/spat/serv") {
            return
        }

        // Parse ControlGRIS message
        if (value.length < 2) {
            return
        }

        const command = value[0]
        const sourceIndex = value[1]

        // Route to all active outputs
        for (let output of outputDevices) {
            if (output.active) {
                const mapped = mapControlGRISMessage(command, sourceIndex, value, output.type)
                if (mapped && mapped.length > 0) {
                    // Send each mapped message to output device
                    for (let msg of mapped) {
                        let full_address = `${output.name}:${msg.address}`
                        Device.write(full_address, msg.value)
                    }
                }
            }
        }
    }

    function mapControlGRISMessage(command, sourceIndex, value, outputType) {
        const messages = []
        
        switch(command) {
            case "pol": // Polar coordinates in radians
                if (value.length >= 7) {
                    const azimuth = value[2]
                    const elevation = value[3]
                    const radius = value[4]
                    const hspan = value[5]
                    const vspan = value[6]
                    
                    messages.push(...mapPolarToOutput(sourceIndex, azimuth, elevation, radius, hspan, vspan, outputType, false))
                }
                break
                
            case "deg": // Polar coordinates in degrees
                if (value.length >= 7) {
                    const azimuth = value[2] * Math.PI / 180.0  // Convert to radians for internal processing
                    const elevation = value[3] * Math.PI / 180.0
                    const radius = value[4]
                    const hspan = value[5]
                    const vspan = value[6]
                    
                    messages.push(...mapPolarToOutput(sourceIndex, azimuth, elevation, radius, hspan, vspan, outputType, true))
                }
                break
                
            case "car": // Cartesian coordinates
                if (value.length >= 7) {
                    const x = value[2]
                    const y = value[3]
                    const z = value[4]
                    const hspan = value[5]
                    const vspan = value[6]
                    
                    messages.push(...mapCartesianToOutput(sourceIndex, x, y, z, hspan, vspan, outputType))
                }
                break
                
            case "clr": // Clear source position
                messages.push(...mapClearToOutput(sourceIndex, outputType))
                break
                
            case "alg": // Algorithm selection (hybrid mode)
                if (value.length >= 3) {
                    const algorithm = value[2]
                    messages.push(...mapAlgorithmToOutput(sourceIndex, algorithm, outputType))
                }
                break
        }
        
        return messages
    }

    function mapPolarToOutput(sourceIndex, azimuth, elevation, radius, hspan, vspan, outputType, isDegrees) {
        const messages = []
        
        switch(outputType) {
            case "SpatGRIS":
                // SpatGRIS score implementation expects individual position values
                messages.push({
                    address: `/${sourceIndex}/azimuth`,
                    value: azimuth
                })
                messages.push({
                    address: `/${sourceIndex}/elevation`,
                    value: elevation
                })
                messages.push({
                    address: `/${sourceIndex}/distance`,
                    value: radius
                })
                if (hspan !== undefined && vspan !== undefined) {
                    messages.push({
                        address: `/${sourceIndex}/hspan`,
                        value: hspan
                    })
                    messages.push({
                        address: `/${sourceIndex}/vspan`,
                        value: vspan
                    })
                }
                break
                
            case "ADM-OSC":
                // ADM-OSC uses spherical coordinates in degrees
                const admAzimuth = azimuth * 180.0 / Math.PI
                const admElevation = elevation * 180.0 / Math.PI
                
                messages.push({
                    address: `/adm/obj/${sourceIndex}/azim`,
                    value: admAzimuth
                })
                messages.push({
                    address: `/adm/obj/${sourceIndex}/elev`,
                    value: admElevation
                })
                messages.push({
                    address: `/adm/obj/${sourceIndex}/dist`,
                    value: radius
                })
                if (hspan !== undefined) {
                    messages.push({
                        address: `/adm/obj/${sourceIndex}/w`,
                        value: hspan * 360  // Convert to degrees
                    })
                }
                if (vspan !== undefined) {
                    messages.push({
                        address: `/adm/obj/${sourceIndex}/h`,
                        value: vspan * 180  // Convert to degrees
                    })
                }
                break
                
            case "SPAT Revolution":
                // SPAT uses /source/N/aed format with degrees
                messages.push({
                    address: `/source/${sourceIndex}/aed`,
                    value: [
                        azimuth * 180.0 / Math.PI,  // Convert to degrees
                        elevation * 180.0 / Math.PI,
                        radius * 100  // SPAT uses percentage (0-100)
                    ]
                })
                if (hspan !== undefined && vspan !== undefined) {
                    messages.push({
                        address: `/source/${sourceIndex}/spread`,
                        value: (hspan + vspan) / 2 * 100  // Average spread as percentage
                    })
                }
                break
        }
        
        return messages
    }

    function mapCartesianToOutput(sourceIndex, x, y, z, hspan, vspan, outputType) {
        const messages = []
        
        switch(outputType) {
            case "SpatGRIS":
                // SpatGRIS score implementation expects individual coordinates
                messages.push({
                    address: `/${sourceIndex}/position`,
                    value: [x,y,z]
                })
                if (hspan !== undefined && vspan !== undefined) {
                    messages.push({
                        address: `/${sourceIndex}/hspan`,
                        value: hspan
                    })
                    messages.push({
                        address: `/${sourceIndex}/vspan`,
                        value: vspan
                    })
                }
                break
                
            case "ADM-OSC":
                // ADM-OSC uses cartesian coordinates
                messages.push({
                    address: `/adm/obj/${sourceIndex}/xyz`,
                    value: [x,y,z]
                })
                if (hspan !== undefined) {
                    messages.push({
                        address: `/adm/obj/${sourceIndex}/w`,
                        value: hspan * 360  // Convert to degrees
                    })
                }
                if (vspan !== undefined) {
                    messages.push({
                        address: `/adm/obj/${sourceIndex}/h`,
                        value: vspan * 180  // Convert to degrees
                    })
                }
                break
                
            case "SPAT Revolution":
                // SPAT uses /source/N/xyz format
                messages.push({
                    address: `/source/${sourceIndex}/xyz`,
                    value: [x, y, z]
                })
                if (hspan !== undefined && vspan !== undefined) {
                    messages.push({
                        address: `/source/${sourceIndex}/spread`,
                        value: (hspan + vspan) / 2 * 100  // Average spread as percentage
                    })
                }
                break
        }
        
        return messages
    }

    function mapClearToOutput(sourceIndex, outputType) {
        const messages = []
        
        switch(outputType) {
            case "SpatGRIS":
                messages.push({
                    address: `/${sourceIndex}/x`,
                    value: 0
                })
                messages.push({
                    address: `/${sourceIndex}/y`,
                    value: 0
                })
                messages.push({
                    address: `/${sourceIndex}/z`,
                    value: 0
                })
                break
                
            case "ADM-OSC":
                messages.push({
                    address: `/adm/obj/${sourceIndex}/x`,
                    value: 0
                })
                messages.push({
                    address: `/adm/obj/${sourceIndex}/y`,
                    value: 0
                })
                messages.push({
                    address: `/adm/obj/${sourceIndex}/z`,
                    value: 0
                })
                break
                
            case "SPAT Revolution":
                messages.push({
                    address: `/source/${sourceIndex}/xyz`,
                    value: [0, 0, 0]
                })
                break
        }
        
        return messages
    }

    function mapAlgorithmToOutput(sourceIndex, algorithm, outputType) {
        const messages = []
        
        switch(outputType) {
            case "SpatGRIS":
                // SpatGRIS might use a different format for algorithm selection
                messages.push({
                    address: `/${sourceIndex}/algorithm`,
                    value: algorithm
                })
                break
                
            case "ADM-OSC":
                // ADM doesn't typically have algorithm selection
                break
                
            case "SPAT Revolution":
                // SPAT has different spatialization modes
                const spatMode = algorithm === "dome" ? "dome" : "panning"
                messages.push({
                    address: `/source/${sourceIndex}/mode`,
                    value: spatMode
                })
                break
        }
        
        return messages
    }
    
    function typeToFormat(type) {
        switch(type) {
            case "SpatGRIS":
              return 0;            
            case "ADM-OSC":
              return 1;            
            case "SPAT Revolution":
              return 2;
            default:
              return 1;
        }
    }
    
    function createOutputDevice(name, host, port, type) {
        Score.removeDevice(name)
        Score.createDevice(name
         , "b96e0e26-c932-40a4-9640-782bf357840e"
         , {              
              "Host": host,
              "Port": port,
              "InputPort": 0,
              "Sources": 128,
              "Format": typeToFormat(type),
              "Programs": 1
           }
        );
      
        outputDevices.push({
            name: name,
            host: host,
            port: port,
            type: type,
            active: true
        })
        
        updateOutputList()
    }

    function removeOutputDevice(index) {
        if (index >= 0 && index < outputDevices.length) {
            Score.removeDevice(outputDevices[index].name)
            outputDevices.splice(index, 1)
            updateOutputList()
        }
    }

    function updateOutputList() {
        outputListModel.clear()
        for (let output of outputDevices) {
            outputListModel.append(output)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // Input Configuration
        GroupBox {
            Layout.fillWidth: true
            Layout.minimumHeight: 100
            Layout.preferredHeight: 100
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
                anchors.fill: parent
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
                    color: "#ffffff"
                    font.pixelSize: Math.min(12, window.height * 0.02)
                    
                    background: Rectangle {
                        color: "#3a3a3a"
                        border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                        radius: 2
                    }
                }
                
                Button {
                    text: "Apply"
                    Layout.preferredWidth: Math.min(80, window.width * 0.1)
                    onClicked: createInputDevice()
                    
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
                
                Item { Layout.fillWidth: true }
            }
        }

        // Output Configuration
        GroupBox {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 200
            title: "Output Devices"
            
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

            ColumnLayout {
                anchors.fill: parent
                spacing: 10


                Item { width: 1; height: 30 }
                // Add Output Form
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 5

                    TextField {
                        id: outputNameField
                        Layout.preferredWidth: Math.max(100, Math.min(150, window.width * 0.15))
                        color: "#ffffff"
                        font.pixelSize: Math.min(12, window.height * 0.02)
                        placeholderText: "Name"
                        
                        background: Rectangle {
                            color: "#3a3a3a"
                            border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                            radius: 2
                        }
                    }
                    
                    TextField {
                        id: outputHostField
                        Layout.preferredWidth: Math.max(100, Math.min(150, window.width * 0.15))
                        text: "127.0.0.1"
                        placeholderText: "IP Address"
                        color: "#ffffff"
                        font.pixelSize: Math.min(12, window.height * 0.02)
                        
                        background: Rectangle {
                            color: "#3a3a3a"
                            border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                            radius: 2
                        }
                    }
                    
                    TextField {
                        id: outputPortField
                        Layout.preferredWidth: Math.max(60, Math.min(100, window.width * 0.1))
                        text: "8000"
                        placeholderText: "Port"
                        color: "#ffffff"
                        font.pixelSize: Math.min(12, window.height * 0.02)
                        
                        background: Rectangle {
                            color: "#3a3a3a"
                            border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                            radius: 2
                        }
                    }
                    
                    ComboBox {
                        id: outputTypeCombo
                        Layout.preferredWidth: Math.max(120, Math.min(180, window.width * 0.18))
                        model: ["SpatGRIS", "ADM-OSC", "SPAT Revolution"]
                        currentIndex: 0
                        
                        background: Rectangle {
                            color: "#3a3a3a"
                            border.color: parent.focus ? "#5a5a5a" : "#4a4a4a"
                            radius: 2
                        }
                        
                        contentItem: Label {
                            text: parent.displayText
                            color: "#ffffff"
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 10
                            font.pixelSize: Math.min(12, window.height * 0.02)
                        }
                        
                        delegate: ItemDelegate {
                            width: parent.width
                            height: 30
                            
                            background: Rectangle {
                                color: parent.hovered ? "#4a4a4a" : "#3a3a3a"
                            }
                            
                            contentItem: Label {
                                text: modelData
                                color: "#ffffff"
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Math.min(12, window.height * 0.02)
                            }
                        }
                        
                        indicator: Canvas {
                            x: parent.width - width - 10
                            y: parent.topPadding + (parent.availableHeight - height) / 2
                            width: 12
                            height: 8
                            contextType: "2d"
                            
                            onPaint: {
                                context.reset()
                                context.moveTo(0, 0)
                                context.lineTo(width, 0)
                                context.lineTo(width / 2, height)
                                context.closePath()
                                context.fillStyle = "#888888"
                                context.fill()
                            }
                        }
                    }
                    
                    Button {
                        text: "Add"
                        Layout.preferredWidth: Math.max(50, Math.min(80, window.width * 0.08))
                        
                        onClicked: {
                            console.log(outputNameField.text, outputHostField.text,outputPortField.text)
                            if (outputNameField.text && outputHostField.text && outputPortField.text) {
                                createOutputDevice(
                                    outputNameField.text,
                                    outputHostField.text,
                                    parseInt(outputPortField.text),
                                    outputTypeCombo.currentText
                                )
                                outputNameField.clear()
                                outputPortField.text = "8000"
                            }
                        }
                        
                        background: Rectangle {
                            color: parent.hovered ? "#5a9a5a" : "#4a8a4a"
                            border.color: "#6aaa6a"
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
                    
                    Item { Layout.fillWidth: true }
                }

                // Output List
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    background: Rectangle {
                        color: "#1a1a1a"
                        radius: 2
                    }

                    ListView {
                        model: ListModel { id: outputListModel }
                        spacing: 2
                        
                        delegate: Rectangle {
                            width: ListView.view.width - 10
                            height: 40
                            color: model.active ? "#3a3a3a" : "#2a2a2a"
                            border.color: "#4a4a4a"
                            radius: 2
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10
                                
                                CheckBox {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    checked: model.active
                                    
                                    onToggled: {
                                        outputDevices[index].active = checked
                                        updateOutputList()
                                    }
                                    
                                    indicator: Rectangle {
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        color: parent.checked ? "#4a8a4a" : "#3a3a3a"
                                        border.color: "#5a5a5a"
                                        radius: 2
                                        
                                        Label {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: "#ffffff"
                                            visible: parent.parent.checked
                                            font.pixelSize: Math.min(12, window.height * 0.02)
                                        }
                                    }
                                }
                                
                                Label {
                                    text: model.name
                                    color: "#ffffff"
                                    Layout.preferredWidth: Math.max(80, window.width * 0.15)
                                    elide: Text.ElideRight
                                    font.pixelSize: Math.min(12, window.height * 0.02)
                                }
                                
                                Label {
                                    text: `${model.type} - ${model.host}:${model.port}`
                                    color: "#aaaaaa"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Math.min(11, window.height * 0.018)
                                }
                                
                                Button {
                                    Layout.preferredWidth: Math.max(60, Math.min(80, window.width * 0.08))
                                    Layout.preferredHeight: 25
                                    text: "Remove"
                                    
                                    onClicked: removeOutputDevice(index)
                                    
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
                                        font.pixelSize: Math.min(11, window.height * 0.018)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Message Monitor
        GroupBox {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(100, Math.min(200, window.height * 0.25))
            Layout.minimumHeight: 80
            title: "Message Monitor"
            
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

            ScrollView {
                anchors.fill: parent
                clip: true
                
                background: Rectangle {
                    color: "#1a1a1a"
                    radius: 2
                }
                
                TextArea {
                    id: messageMonitor
                    readOnly: true
                    selectByMouse: true
                    color: "#00ff00"
                    font.family: "Consolas, Monaco, monospace"
                    font.pixelSize: Math.min(11, window.height * 0.018)
                    wrapMode: TextArea.Wrap
                    padding: 8
                    
                    background: Rectangle {
                        color: "transparent"
                    }
                }
            }
        }

        // Presets and controls
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 30
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
                onClicked: createOutputDevice("SpatGRIS_1", "127.0.0.1", 18042, "SpatGRIS")
                
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
                onClicked: createOutputDevice("ADM_1", "127.0.0.1", 9000, "ADM-OSC")
                
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
                onClicked: createOutputDevice("SPAT_1", "127.0.0.1", 8088, "SPAT Revolution")
                
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

            Item { Layout.fillWidth: true }

            Button {
                Layout.preferredWidth: Math.max(70, Math.min(100, window.width * 0.1))
                text: "Clear All"
                
                onClicked: {
                    while (outputDevices.length > 0) {
                        removeOutputDevice(0)
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
    }
}
