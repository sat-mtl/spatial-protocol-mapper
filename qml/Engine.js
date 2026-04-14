function restoreSavedSettings() {
    inputPortField.text = appSettings.listenPort;

    // Restore saved output devices
    try {
        const savedOutputs = JSON.parse(appSettings.savedOutputDevices);
        for (let output of savedOutputs) {
            createOutputDevice(output.name, output.host, output.port, output.type);
            // Restore active state and source index offset after creation
            const lastIdx = outputDevices.length - 1
            if (output.sourceIndexOffset) {
                outputDevices[lastIdx].sourceIndexOffset = output.sourceIndexOffset
            }

            if (output.active === false) {
                outputDevices[lastIdx].active = false
            }
            updateOutputList();
        }
    } catch (e) {
        console.log("Could not restore saved outputs:", e);
    }
}

function saveOutputDevices() {
    const toSave = outputDevices.map(function (d) {
        return {
            name: d.name,
            host: d.host,
            port: d.port,
            type: d.type,
            active: d.active,
            sourceIndexOffset: d.sourceIndexOffset || 0
        };
    });
    appSettings.savedOutputDevices = JSON.stringify(toSave);
}

var g_lastInputLogTimestamp = 0;
var g_lastOutputLogTimestamp = 0;
function rateLimitInputLog()
{
    const ts = Util.timestamp();
    if((ts - g_lastInputLogTimestamp) < appSettings.monitorInterval)
      return false;
    g_lastInputLogTimestamp = ts;
    return true;
}
function rateLimitOutputLog()
{
    const ts = Util.timestamp();
    if((ts - g_lastOutputLogTimestamp) < appSettings.monitorInterval)
      return false;
    g_lastOutputLogTimestamp = ts;
    return true;
}

function logMessage(message) {
    messageMonitor.append(message);
    // Update monitor
    if (messageMonitor.lineCount > 15) {
        messageMonitor.remove(0, messageMonitor.text.indexOf('\n') + 1);
    }
}

function onInputValueReceived(address, value) {
    if (appSettings.logReceivedMessages && messageMonitor.visible && rateLimitInputLog()) {
        logMessage(`IN: ${address} = ${JSON.stringify(value)}`);
    }

    // Only process /spat/serv messages from ControlGRIS
    if (address !== "/spat/serv") {
        return;
    }

    // Parse ControlGRIS message into a normalized form:
    //   command    : "pol" | "deg" | "car" | "clr" | "alg"
    //   sourceIndex: 1-based source index (or -1 if n/a)
    //   args       : command-dependent payload:
    //     pol/deg: [azimuth, elevation, radius, hspan, vspan]
    //     car    : [x, y, z, hspan, vspan]
    //     clr    : []
    //     alg    : [algorithm]
    if (value.length < 2) {
        return;
    }

    var command, sourceIndex, args;
    if (typeof value[0] === "number") {
        // Legacy SpatGRIS format: [sourceIndex, az, el, hspan, vspan, radius, reserved]
        // This is polar in radians; rewrite to the canonical "pol" shape.
        if (value.length < 7) return;
        command = "pol";
        sourceIndex = value[0];
        args = [value[1], value[2], value[5], value[3], value[4]];
    } else {
        command = value[0];
        sourceIndex = (typeof value[1] === "number") ? value[1] : -1;
        args = value.slice(2);
    }

    // Route to all active outputs
    for (let output of outputDevices) {
        if (!output.active || !output.udp) continue;

        const idx = sourceIndex + (output.sourceIndexOffset || 0);
        const mapped = mapMessage(command, idx, args, output.type);
        if (!mapped || mapped.length === 0) continue;

        for (let msg of mapped) {
            // outboundUDP.osc() expects a JS array for the arguments —
            // wrap scalar values so "/a/b" with value 0 doesn't crash.
            const args = Array.isArray(msg.value) ? msg.value : [msg.value];
            output.udp.osc(msg.address, args);
            if (appSettings.logSentMessages && messageMonitor.visible && rateLimitOutputLog()) {
                logMessage(`OUT: ${output.name} ${msg.address} = ${JSON.stringify(msg.value)}`);
            }
        }
    }
}

function mapMessage(command, idx, args, outputType) {
    switch (outputType) {
    case "SpatGRIS":       return mapForSpatGRIS(command, idx, args);
    case "ADM-OSC":        return mapForADM(command, idx, args);
    case "SPAT Revolution": return mapForSPAT(command, idx, args);
    }
    return [];
}

// ----- SpatGRIS: pass /spat/serv through verbatim -----
// The SpatGRIS server speaks /spat/serv natively, so we re-emit the
// command with the exact coordinate system we received. No lossy
// polar<->cartesian round-trip.
function mapForSpatGRIS(command, idx, args) {
    switch (command) {
    case "pol":
    case "deg":
    case "car":
        if (args.length < 5) return [];
        return [{
            address: "/spat/serv",
            value: [command, idx, args[0], args[1], args[2], args[3], args[4]]
        }];
    case "clr":
        return [{ address: "/spat/serv", value: ["clr", idx] }];
    case "alg":
        if (args.length < 1) return [];
        // alg idx <dome|cube>
        return [{ address: "/spat/serv", value: ["alg", idx, args[0]] }];
    }
    return [];
}

// ----- ADM-OSC (v1.0) -----
// Conventions:
//   - Azimuth: SpatGRIS uses −90° = left / +90° = right (example in spec:
//     "deg 7 -90.0 ... moves source #7 at the extreme left").
//     ADM uses +90° = left / −90° = right. → sign flipped.
//   - Elevation: both use 0° = horizon, +90° = above. → no change.
//   - Cartesian axes match: x = L/R, y = B/F, z = D/U with same signs.
// Ranges differ (SpatGRIS radius ∈ [−3, 3], xyz ∈ [−1.66, 1.66];
// ADM dist ∈ [0, 1], xyz ∈ [−1, 1]). Per ADM-OSC §9 receivers must clamp,
// so we pass values through unchanged rather than impose a scaling that
// would change the physical position.
// ADM has no vertical-extent address — vspan is dropped.
// Packed /aed and /xyz are used per the spec's atomicity recommendation.
function mapForADM(command, idx, args) {
    switch (command) {
    case "pol":
        if (args.length < 5) return [];
        return polarToADM(idx, args[0], args[1], args[2], args[3]);
    case "deg":
        if (args.length < 5) return [];
        return polarToADM(idx,
                          args[0] * Math.PI / 180.0,
                          args[1] * Math.PI / 180.0,
                          args[2], args[3]);
    case "car":
        if (args.length < 5) return [];
        return cartesianToADM(idx, args[0], args[1], args[2], args[3]);
    case "clr":
        // Packed xyz for atomic reset.
        return [{ address: `/adm/obj/${idx}/xyz`, value: [0, 0, 0] }];
    case "alg":
        // ADM has no algorithm concept.
        return [];
    }
    return [];
}

function polarToADM(idx, azimuthRad, elevationRad, radius, hspan) {
    const messages = [{
        address: `/adm/obj/${idx}/aed`,
        value: [
            -azimuthRad   * 180.0 / Math.PI,  // SpatGRIS → ADM azimuth sign flip
             elevationRad * 180.0 / Math.PI,
             radius
        ]
    }];
    if (hspan !== undefined) {
        // ADM /w is normalized [0, 1]; SpatGRIS hspan is already [0, 1].
        messages.push({ address: `/adm/obj/${idx}/w`, value: hspan });
    }
    return messages;
}

function cartesianToADM(idx, x, y, z, hspan) {
    const messages = [{
        address: `/adm/obj/${idx}/xyz`,
        value: [x, y, z]
    }];
    if (hspan !== undefined) {
        messages.push({ address: `/adm/obj/${idx}/w`, value: hspan });
    }
    return messages;
}

// ----- SPAT Revolution: /source/N/aed or /source/N/xyz -----
function mapForSPAT(command, idx, args) {
    switch (command) {
    case "pol":
        if (args.length < 5) return [];
        return polarToSPAT(idx, args[0], args[1], args[2], args[3], args[4]);
    case "deg":
        if (args.length < 5) return [];
        return polarToSPAT(idx,
                           args[0] * Math.PI / 180.0,
                           args[1] * Math.PI / 180.0,
                           args[2], args[3], args[4]);
    case "car":
        if (args.length < 5) return [];
        return cartesianToSPAT(idx, args[0], args[1], args[2], args[3], args[4]);
    case "clr":
        return [{ address: `/source/${idx}/xyz`, value: [0, 0, 0] }];
    case "alg":
        if (args.length < 1) return [];
        return [{
            address: `/source/${idx}/mode`,
            value: args[0] === "dome" ? "dome" : "panning"
        }];
    }
    return [];
}

function polarToSPAT(idx, azimuthRad, elevationRad, radius, hspan, vspan) {
    const messages = [{
        address: `/source/${idx}/aed`,
        value: [
            azimuthRad   * 180.0 / Math.PI,
            elevationRad * 180.0 / Math.PI,
            radius * 100  // SPAT uses percentage (0-100)
        ]
    }];
    if (hspan !== undefined && vspan !== undefined) {
        messages.push({
            address: `/source/${idx}/spread`,
            value: (hspan + vspan) / 2 * 100
        });
    }
    return messages;
}

function cartesianToSPAT(idx, x, y, z, hspan, vspan) {
    const messages = [{
        address: `/source/${idx}/xyz`,
        value: [x, y, z]
    }];
    if (hspan !== undefined && vspan !== undefined) {
        messages.push({
            address: `/source/${idx}/spread`,
            value: (hspan + vspan) / 2 * 100
        });
    }
    return messages;
}

// ----- Output device lifecycle -----
// Each output device is backed by a raw outbound UDP socket.
// We format OSC entirely in JS (mapForXxx above) and hand the
// result to udp.osc(addr, values).
function openOutputSocket(dev) {
    if (dev.udp) {
        try { dev.udp.close(); } catch (e) {}
        dev.udp = null;
    }
    try {
        dev.udp = Protocols.outboundUDP({
            Transport: { Host: dev.host, Port: dev.port },
            onError: function() {
                console.log("Output socket error on", dev.name, dev.host + ":" + dev.port);
            }
        });
    } catch (e) {
        console.log("Failed to open outbound UDP to", dev.host, dev.port, e);
        dev.udp = null;
    }
}

function createOutputDevice(name, host, port, type) {
    const dev = {
        name: name,
        host: host,
        port: port,
        type: type,
        active: true,
        sourceIndexOffset: 0,
        udp: null
    };
    openOutputSocket(dev);
    outputDevices.push(dev);
    updateOutputList();
    saveOutputDevices();
}

function removeOutputDevice(index) {
    if (index >= 0 && index < outputDevices.length) {
        const dev = outputDevices[index];
        if (dev.udp) {
            try { dev.udp.close(); } catch (e) {}
            dev.udp = null;
        }
        outputDevices.splice(index, 1);
        updateOutputList();
        saveOutputDevices();
    }
}

function updateOutputList() {
    outputListModel.clear();
    for (let output of outputDevices) {
        // Only expose display fields — the `udp` socket is a QObject
        // and doesn't belong in the ListModel.
        outputListModel.append({
            name: output.name,
            host: output.host,
            port: output.port,
            type: output.type,
            active: output.active,
            sourceIndexOffset: output.sourceIndexOffset || 0
        });
    }
}

function closeInputDevice() {
    if (udpInput)
        udpInput.close();
    udpInput = null;
    oscInput = null;
    inputListening = false;
    inputPortError = "";
}

function createInputDevice(inputPort) {
    closeInputDevice();
    console.log("Creating new device", inputPort);

    Qt.callLater(function () {
        oscInput = Protocols.osc({
            onOsc: function (a, v) {
                onInputValueReceived(a, v);
            }
        });
        udpInput = Protocols.inboundUDP({
            Transport: {
                Bind: "0.0.0.0",
                Port: inputPort
            },
            onMessage: function (bytes) {
                oscInput.processMessage(bytes);
            }
        });

        if (udpInput) {
            inputListening = true;
        } else {
            inputPortError = "Failed to open port " + inputPort + " (already in use?)";
        }
    });
}
