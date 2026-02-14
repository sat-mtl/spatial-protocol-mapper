function restoreSavedSettings() {
    inputPortField.text = appSettings.listenPort;

    // Restore saved output devices
    try {
        const savedOutputs = JSON.parse(appSettings.savedOutputDevices);
        for (let output of savedOutputs) {
            createOutputDevice(output.name, output.host, output.port, output.type);
            // Restore active state after creation
            if (output.active === false) {
                outputDevices[outputDevices.length - 1].active = false;
                updateOutputList();
            }
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
            active: d.active
        };
    });
    appSettings.savedOutputDevices = JSON.stringify(toSave);
}

function logMessage(message) {
    messageMonitor.append(message);
    // Update monitor
    if (messageMonitor.lineCount > 15) {
        messageMonitor.remove(0, messageMonitor.text.indexOf('\n') + 1);
    }
}

function onInputValueReceived(address, value) {
    if (appSettings.logReceivedMessages) {
        logMessage(`IN: ${address} = ${JSON.stringify(value)}`);
    }

    // Only process /spat/serv messages from ControlGRIS
    if (address !== "/spat/serv") {
        return;
    }

    // Parse ControlGRIS message
    if (value.length < 2) {
        return;
    }

    const command = value[0];
    const sourceIndex = value[1];

    // Route to all active outputs
    for (let output of outputDevices) {
        if (output.active) {
            const mapped = mapControlGRISMessage(command, sourceIndex, value, output.type);
            if (mapped && mapped.length > 0) {
                // Send each mapped message to output device
                for (let msg of mapped) {
                    let full_address = `${output.name}:${msg.address}`;
                    Device.write(full_address, msg.value);
                    if (appSettings.logSentMessages) {
                        logMessage(`OUT: ${full_address} = ${JSON.stringify(msg.value)}`);
                    }
                }
            }
        }
    }
}

function mapControlGRISMessage(command, sourceIndex, value, outputType) {
    const messages = [];

    switch (command) {
    case "pol": // Polar coordinates in radians
        if (value.length >= 7) {
            const azimuth = value[2];
            const elevation = value[3];
            const radius = value[4];
            const hspan = value[5];
            const vspan = value[6];

            messages.push(...mapPolarToOutput(sourceIndex, azimuth, elevation, radius, hspan, vspan, outputType, false));
        }
        break;
    case "deg": // Polar coordinates in degrees
        if (value.length >= 7) {
            const azimuth = value[2] * Math.PI / 180.0;  // Convert to radians for internal processing
            const elevation = value[3] * Math.PI / 180.0;
            const radius = value[4];
            const hspan = value[5];
            const vspan = value[6];

            messages.push(...mapPolarToOutput(sourceIndex, azimuth, elevation, radius, hspan, vspan, outputType, true));
        }
        break;
    case "car": // Cartesian coordinates
        if (value.length >= 7) {
            const x = value[2];
            const y = value[3];
            const z = value[4];
            const hspan = value[5];
            const vspan = value[6];

            messages.push(...mapCartesianToOutput(sourceIndex, x, y, z, hspan, vspan, outputType));
        }
        break;
    case "clr": // Clear source position
        messages.push(...mapClearToOutput(sourceIndex, outputType));
        break;
    case "alg": // Algorithm selection (hybrid mode)
        if (value.length >= 3) {
            const algorithm = value[2];
            messages.push(...mapAlgorithmToOutput(sourceIndex, algorithm, outputType));
        }
        break;
    }

    return messages;
}

function mapPolarToOutput(sourceIndex, azimuth, elevation, radius, hspan, vspan, outputType, isDegrees) {
    const messages = [];

    switch (outputType) {
    case "SpatGRIS":
        // SpatGRIS score implementation expects individual position values
        messages.push({
            address: `/${sourceIndex}/azimuth`,
            value: azimuth
        });
        messages.push({
            address: `/${sourceIndex}/elevation`,
            value: elevation
        });
        messages.push({
            address: `/${sourceIndex}/distance`,
            value: radius
        });
        if (hspan !== undefined && vspan !== undefined) {
            messages.push({
                address: `/${sourceIndex}/hspan`,
                value: hspan
            });
            messages.push({
                address: `/${sourceIndex}/vspan`,
                value: vspan
            });
        }
        break;
    case "ADM-OSC":
        // ADM-OSC uses spherical coordinates in degrees
        const admAzimuth = azimuth * 180.0 / Math.PI;
        const admElevation = elevation * 180.0 / Math.PI;

        messages.push({
            address: `/adm/obj/${sourceIndex}/azim`,
            value: admAzimuth
        });
        messages.push({
            address: `/adm/obj/${sourceIndex}/elev`,
            value: admElevation
        });
        messages.push({
            address: `/adm/obj/${sourceIndex}/dist`,
            value: radius
        });
        if (hspan !== undefined) {
            messages.push({
                address: `/adm/obj/${sourceIndex}/w`,
                value: hspan * 360  // Convert to degrees
            });
        }
        if (vspan !== undefined) {
            messages.push({
                address: `/adm/obj/${sourceIndex}/h`,
                value: vspan * 180  // Convert to degrees
            });
        }
        break;
    case "SPAT Revolution":
        // SPAT uses /source/N/aed format with degrees
        messages.push({
            address: `/source/${sourceIndex}/aed`,
            value: [azimuth * 180.0 / Math.PI  // Convert to degrees
                , elevation * 180.0 / Math.PI, radius * 100  // SPAT uses percentage (0-100)
            ]
        });
        if (hspan !== undefined && vspan !== undefined) {
            messages.push({
                address: `/source/${sourceIndex}/spread`,
                value: (hspan + vspan) / 2 * 100  // Average spread as percentage
            });
        }
        break;
    }

    return messages;
}

function mapCartesianToOutput(sourceIndex, x, y, z, hspan, vspan, outputType) {
    const messages = [];

    switch (outputType) {
    case "SpatGRIS":
        // SpatGRIS score implementation expects individual coordinates
        messages.push({
            address: `/${sourceIndex}/position`,
            value: [x, y, z]
        });
        if (hspan !== undefined && vspan !== undefined) {
            messages.push({
                address: `/${sourceIndex}/hspan`,
                value: hspan
            });
            messages.push({
                address: `/${sourceIndex}/vspan`,
                value: vspan
            });
        }
        break;
    case "ADM-OSC":
        // ADM-OSC uses cartesian coordinates
        messages.push({
            address: `/adm/obj/${sourceIndex}/xyz`,
            value: [x, y, z]
        });
        if (hspan !== undefined) {
            messages.push({
                address: `/adm/obj/${sourceIndex}/w`,
                value: hspan * 360  // Convert to degrees
            });
        }
        if (vspan !== undefined) {
            messages.push({
                address: `/adm/obj/${sourceIndex}/h`,
                value: vspan * 180  // Convert to degrees
            });
        }
        break;
    case "SPAT Revolution":
        // SPAT uses /source/N/xyz format
        messages.push({
            address: `/source/${sourceIndex}/xyz`,
            value: [x, y, z]
        });
        if (hspan !== undefined && vspan !== undefined) {
            messages.push({
                address: `/source/${sourceIndex}/spread`,
                value: (hspan + vspan) / 2 * 100  // Average spread as percentage
            });
        }
        break;
    }

    return messages;
}

function mapClearToOutput(sourceIndex, outputType) {
    const messages = [];

    switch (outputType) {
    case "SpatGRIS":
        messages.push({
            address: `/${sourceIndex}/x`,
            value: 0
        });
        messages.push({
            address: `/${sourceIndex}/y`,
            value: 0
        });
        messages.push({
            address: `/${sourceIndex}/z`,
            value: 0
        });
        break;
    case "ADM-OSC":
        messages.push({
            address: `/adm/obj/${sourceIndex}/x`,
            value: 0
        });
        messages.push({
            address: `/adm/obj/${sourceIndex}/y`,
            value: 0
        });
        messages.push({
            address: `/adm/obj/${sourceIndex}/z`,
            value: 0
        });
        break;
    case "SPAT Revolution":
        messages.push({
            address: `/source/${sourceIndex}/xyz`,
            value: [0, 0, 0]
        });
        break;
    }

    return messages;
}

function mapAlgorithmToOutput(sourceIndex, algorithm, outputType) {
    const messages = [];

    switch (outputType) {
    case "SpatGRIS":
        // SpatGRIS might use a different format for algorithm selection
        messages.push({
            address: `/${sourceIndex}/algorithm`,
            value: algorithm
        });
        break;
    case "ADM-OSC":
        // ADM doesn't typically have algorithm selection
        break;
    case "SPAT Revolution":
        // SPAT has different spatialization modes
        const spatMode = algorithm === "dome" ? "dome" : "panning";
        messages.push({
            address: `/source/${sourceIndex}/mode`,
            value: spatMode
        });
        break;
    }

    return messages;
}

function typeToFormat(type) {
    switch (type) {
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
    Score.removeDevice(name);
    Score.createDevice(name, "b96e0e26-c932-40a4-9640-782bf357840e", {
        "Host": host,
        "Port": port,
        "InputPort": 0,
        "Sources": 128,
        "Format": typeToFormat(type),
        "Programs": 1
    });

    outputDevices.push({
        name: name,
        host: host,
        port: port,
        type: type,
        active: true
    });

    updateOutputList();
    saveOutputDevices();
}

function removeOutputDevice(index) {
    if (index >= 0 && index < outputDevices.length) {
        Score.removeDevice(outputDevices[index].name);
        outputDevices.splice(index, 1);
        updateOutputList();
        saveOutputDevices();
    }
}

function updateOutputList() {
    outputListModel.clear();
    for (let output of outputDevices) {
        outputListModel.append(output);
    }
}

function createInputDevice(inputPort) {
    console.log("Cleared old device");
    if (udpInput)
        udpInput.close();
    udpInput = null;
    oscInput = null;
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
    });
}
