.import "LogQueue.js" as LogQueue

// Routing engine.
//
// The model is a matrix: any number of inputs, any number of outputs, and an
// explicit route for each connection between them. Basic mode is the special
// case of one input, not a separate code path.
//
//   inputs  [{ id, name, protocol, port, listening, error, udp, osc, admState }]
//   outputs [{ id, name, protocol, host, port, udp }]
//   routes  [{ inputId, outputId, enabled, sourceOffset, srcMin, srcMax }]
//
// `srcMin`/`srcMax` are null when the route carries every source. The filter
// tests the *incoming* source index, before `sourceOffset` is applied, so the
// numbers in the UI match the numbers on the sender.
//
// Free variables (inputs, outputs, routes, appSettings, the list models,
// messageMonitor, monitorActive, Protocols) resolve against Main.qml, which is
// the only file that imports this script.

// ----- Identity --------------------------------------------------------- //
// Routes reference devices by id, so ids must outlive any array position.
var g_nextId = 1;

function nextId() {
    return g_nextId++;
}

function findInput(id) {
    for (let i of inputs)
        if (i.id === id) return i;
    return null;
}

function findOutput(id) {
    for (let o of outputs)
        if (o.id === id) return o;
    return null;
}

function findRoute(inputId, outputId) {
    for (let r of routes)
        if (r.inputId === inputId && r.outputId === outputId) return r;
    return null;
}

// ----- Dispatch index --------------------------------------------------- //
// Rebuilt on every structural change so the message path is a lookup and a
// loop rather than a scan of every route with a findOutput() inside it.
var g_linksByInput = {};

function reindexRoutes() {
    g_linksByInput = {};
    for (let r of routes) {
        if (!r.enabled) continue;
        const out = findOutput(r.outputId);
        if (!out) continue;
        if (!g_linksByInput[r.inputId])
            g_linksByInput[r.inputId] = [];
        g_linksByInput[r.inputId].push({ route: r, output: out });
    }
}

// A range filter is about sources. Commands that carry no source index — a
// global command, /adm/lis, /adm/env, anything forwarded verbatim — would
// otherwise be silenced on every filtered route, so they bypass it.
function routeAccepts(route, sourceIndex) {
    if (sourceIndex < 0) return true;
    if (route.srcMin !== null && route.srcMin !== undefined && sourceIndex < route.srcMin)
        return false;
    if (route.srcMax !== null && route.srcMax !== undefined && sourceIndex > route.srcMax)
        return false;
    return true;
}

// ----- Message path ----------------------------------------------------- //

function onInputValueReceived(inp, address, value) {
    if (appSettings.logReceivedMessages && monitorActive) {
        LogQueue.pushInput(`IN  [${inp.name}] ${address} = ${JSON.stringify(value)}`);
    }

    const links = g_linksByInput[inp.id];
    if (!links || links.length === 0) return;

    // Normalize the incoming message to an internal SpatGRIS-style form:
    //   command    : "pol" | "deg" | "car" | "clr" | "alg"
    //   sourceIndex: 1-based source index (or -1 if n/a)
    //   args       : command-dependent payload
    //     pol   : [azimuthRad, elevationRad, radius, hspan, vspan]
    //     deg   : [azimuthDeg, elevationDeg, radius, hspan, vspan]
    //     car   : [x, y, z, hspan, vspan]
    //     clr   : []
    //     alg   : [algorithm]
    // Angles and axes use SpatGRIS conventions internally
    // (negative azimuth = left). Each output's mapper applies its own flips.
    const norm = applyInputScale(inp, parseInput(inp, address, value));

    if (norm) {
        for (let link of links) {
            const out = link.output;
            if (!out.udp) continue;
            if (!routeAccepts(link.route, norm.sourceIndex)) continue;

            const idx = norm.sourceIndex + (link.route.sourceOffset || 0);
            const mapped = mapMessage(norm.command, idx, norm.args, out.protocol, norm);
            if (!mapped || mapped.length === 0) continue;

            for (let msg of mapped) {
                // outboundUDP.osc() expects a JS array for the arguments —
                // wrap scalar values so "/a/b" with value 0 doesn't crash.
                const oscArgs = Array.isArray(msg.value) ? msg.value : [msg.value];
                out.udp.osc(msg.address, oscArgs);
                if (appSettings.logSentMessages && monitorActive) {
                    LogQueue.pushOutput(`OUT [${out.name}] ${msg.address} = ${JSON.stringify(msg.value)}`);
                }
            }
        }
        return;
    }

    // Messages we couldn't translate that still belong to a protocol
    // we have outputs for: pass them through verbatim. This lets
    // ADM-specific features (gain, mute, name, /adm/lis, /adm/env, …)
    // reach ADM-OSC outputs even though we don't understand them.
    if (address.startsWith("/adm/")) {
        forwardAdmRaw(inp, links, address, value);
    }
}

// An input declares what it speaks; "Auto" keeps the original behaviour of
// deciding from the address.
function parseInput(inp, address, value) {
    switch (inp.protocol) {
    case "SpatGRIS":
        return address.startsWith("/spat/serv") ? parseSpatGRISInput(value) : null;
    case "ADM-OSC":
        return address.startsWith("/adm/obj/") ? parseADMInput(inp, address, value) : null;
    case "SPAT Revolution":
        return address.startsWith("/source/") ? parseSPATInput(inp, address, value) : null;
    }
    if (address.startsWith("/spat/serv")) return parseSpatGRISInput(value);
    if (address.startsWith("/adm/obj/")) return parseADMInput(inp, address, value);
    if (address.startsWith("/source/")) return parseSPATInput(inp, address, value);
    return null;
}

function forwardAdmRaw(inp, links, address, value) {
    const oscArgs = Array.isArray(value) ? value : [value];

    // Only /adm/obj/{n}/… carries a source index; /adm/lis and /adm/env don't.
    // Both the range filter and the offset key off that.
    const m = address.match(/^\/adm\/obj\/(\d+)(\/.*)$/);
    const sourceIndex = m ? parseInt(m[1]) : -1;

    for (let link of links) {
        const out = link.output;
        if (!out.udp) continue;
        if (out.protocol !== "ADM-OSC") continue;
        if (!routeAccepts(link.route, sourceIndex)) continue;

        let outAddress = address;
        const offset = link.route.sourceOffset || 0;
        if (offset !== 0 && m) {
            outAddress = `/adm/obj/${sourceIndex + offset}${m[2]}`;
        }

        out.udp.osc(outAddress, oscArgs);
        if (appSettings.logSentMessages && monitorActive) {
            LogQueue.pushOutput(`OUT [${out.name}] ${outAddress} = ${JSON.stringify(value)}`);
        }
    }
}

// ----- Per-input scaling ------------------------------------------------ //
// Corrects a sender whose room is a different size, or whose axes are mirrored
// relative to ours: a negative factor flips that axis. Applied once, on the
// canonical form, before any route sees the message, so every output fed by an
// input agrees on where the source is.
//
// SpatGRIS convention: azimuth is measured from the front (+y) toward the
// right (+x), elevation from the horizon toward +z.
function sphericalToCartesian(az, el, r) {
    const ce = Math.cos(el);
    return { x: r * ce * Math.sin(az), y: r * ce * Math.cos(az), z: r * Math.sin(el) };
}

function cartesianToSpherical(x, y, z) {
    const r = Math.sqrt(x * x + y * y + z * z);
    // At the origin there is no direction to report; asin(0/0) would be NaN.
    if (r < 1e-12) return { az: 0, el: 0, r: 0 };
    return { az: Math.atan2(x, y), el: Math.asin(z / r), r: r };
}

function scaleOf(inp, axis) {
    const v = inp[axis];
    return (v === undefined || v === null) ? 1 : v;
}

function inputHasScale(inp) {
    return scaleOf(inp, "scaleX") !== 1
        || scaleOf(inp, "scaleY") !== 1
        || scaleOf(inp, "scaleZ") !== 1;
}

// Returns a new normalized message, or the one it was given when there is
// nothing to do — so an unscaled input keeps today's exact values and pays
// nothing for the feature.
function applyInputScale(inp, norm) {
    if (!norm || !inputHasScale(inp)) return norm;

    const sx = scaleOf(inp, "scaleX");
    const sy = scaleOf(inp, "scaleY");
    const sz = scaleOf(inp, "scaleZ");
    const a = norm.args;

    // Note what is *not* carried over: `legacyArgs`. A SpatGRIS output re-emits
    // that payload verbatim, which would put the unscaled position back on the
    // wire and silently ignore the input's scaling.
    switch (norm.command) {
    case "car":
        if (a.length < 3) return norm;
        return {
            command: "car",
            sourceIndex: norm.sourceIndex,
            args: [a[0] * sx, a[1] * sy, a[2] * sz].concat(a.slice(3))
        };
    case "pol":
    case "deg": {
        if (a.length < 3) return norm;
        // Polar is scaled by going through cartesian and back. That is a
        // float round trip, which is why identity returns early above.
        const toRad = (norm.command === "deg") ? Math.PI / 180 : 1;
        const p = sphericalToCartesian(a[0] * toRad, a[1] * toRad, a[2]);
        const q = cartesianToSpherical(p.x * sx, p.y * sy, p.z * sz);
        return {
            command: norm.command,
            sourceIndex: norm.sourceIndex,
            args: [q.az / toRad, q.el / toRad, q.r].concat(a.slice(3))
        };
    }
    }
    // clr, alg and anything forwarded verbatim carry no position.
    return norm;
}

// ----- Input parsing: /spat/serv ---------------------------------------- //
const HALF_PI = Math.PI / 2.;
function parseSpatGRISInput(value) {
    if (!value || value.length < 2) return null;

    if (typeof value[0] === "number") {
        // Legacy format: [sourceIndex, az, el, hspan, vspan, radius, reserved]
        // Polar in radians; rewrite to canonical "pol" shape.
        if (value.length < 7) return null;
        // Keep the original payload: SpatGRIS routes the legacy form through a
        // *cylindrical* LegacyLbapPosition::toPosition() in Cube/MBAP mode, but
        // routes "pol" through a *spherical* conversion. Rewriting legacy to
        // "pol" therefore moves the source (az=0, colat=pi/4, dist=1 lands at
        // (0,0.707,0.707) instead of (0,1,0.5)). Outputs that speak /spat/serv
        // natively re-emit `legacyArgs` unchanged; every other output uses the
        // normalized "pol" form below, which is correct for them.
        return {
            command: "pol",
            sourceIndex: 1+value[0],
            args: [value[1], HALF_PI - value[2], value[5], value[3] / 2., value[4] * 2.],
            legacyArgs: value.slice(1)
        };
    }
    return {
        command: value[0],
        sourceIndex: (typeof value[1] === "number") ? value[1] : -1,
        args: value.slice(2)
    };
}

// ----- Input parsing: /adm/obj/{n}/… ------------------------------------ //
// ADM sends per-parameter messages, not atomic packets, so we maintain
// per-source state and emit a complete SpatGRIS-form command on every
// incoming update. The last coordinate family written (polar vs cartesian)
// determines whether we emit a "deg" or "car" command downstream.
//
// The accumulator belongs to the input device: two ADM senders on different
// ports address their own source 1, and a shared table would let one overwrite
// the other's coordinates.
function getAdmSource(inp, n) {
    if (!inp.admState)
        inp.admState = {};
    if (!inp.admState[n]) {
        // Defaults per ADM-OSC spec:
        //   azim, elev: (unspecified) → 0
        //   dist      : 1.0 (on reference sphere)
        //   xyz       : 0
        //   w         : 0
        inp.admState[n] = {
            azim: 0, elev: 0, dist: 1.0,
            x: 0, y: 0, z: 0,
            w: 0,
            lastMode: "car"
        };
    }
    return inp.admState[n];
}

function parseADMInput(inp, address, value) {
    // Match /adm/obj/<n>/<param> exactly (no wildcards).
    const m = address.match(/^\/adm\/obj\/(\d+)\/(\w+)$/);
    if (!m) return null;

    const n = parseInt(m[1]);
    const param = m[2];
    const s = getAdmSource(inp, n);

    if (!value) return null;

    switch (param) {
    case "aed":
        if (value.length < 3) return null;
        s.azim = value[0]; s.elev = value[1]; s.dist = value[2];
        s.lastMode = "pol";
        break;
    case "azim":
        if (value.length < 1) return null;
        s.azim = value[0]; s.lastMode = "pol";
        break;
    case "elev":
        if (value.length < 1) return null;
        s.elev = value[0]; s.lastMode = "pol";
        break;
    case "dist":
        if (value.length < 1) return null;
        s.dist = value[0]; s.lastMode = "pol";
        break;
    case "xyz":
        if (value.length < 3) return null;
        s.x = value[0]; s.y = value[1]; s.z = value[2];
        s.lastMode = "car";
        break;
    case "xy":
        if (value.length < 2) return null;
        s.x = value[0]; s.y = value[1];
        s.lastMode = "car";
        break;
    case "x":
        if (value.length < 1) return null;
        s.x = value[0]; s.lastMode = "car";
        break;
    case "y":
        if (value.length < 1) return null;
        s.y = value[0]; s.lastMode = "car";
        break;
    case "z":
        if (value.length < 1) return null;
        s.z = value[0]; s.lastMode = "car";
        break;
    case "w":
        if (value.length < 1) return null;
        s.w = value[0];
        // Width alone doesn't switch coordinate mode; re-emit with current mode.
        break;
    default:
        // gain/mute/name/dref/dmax — no equivalent in our internal model.
        return null;
    }

    // Emit in SpatGRIS-convention internal form.
    // Axes match (x=L/R, y=B/F, z=D/U with same sign), so xyz passes through.
    // ADM azimuth: +90° = left. SpatGRIS azimuth: -90° = left. → sign flip.
    // ADM has no vertical extent → vspan = 0.
    if (s.lastMode === "pol") {
        return {
            command: "deg",
            sourceIndex: n,
            args: [-s.azim, s.elev, s.dist, s.w, 0]
        };
    } else {
        return {
            command: "car",
            sourceIndex: n,
            args: [s.x, s.y, s.z, s.w, 0]
        };
    }
}

// ----- Input parsing: /source/{n}/… (SPAT Revolution) ------------------- //
// The mirror of mapForSPAT, so a SPAT source round-trips unchanged: azimuth
// keeps the SpatGRIS sign (SPAT shares it), radius arrives as a percentage,
// and spread is one figure that fills both extents.
//
// Like ADM, SPAT sends one parameter per message, so the accumulator lives on
// the input device.
function getSpatSource(inp, n) {
    if (!inp.spatState)
        inp.spatState = {};
    if (!inp.spatState[n]) {
        inp.spatState[n] = {
            azim: 0, elev: 0, dist: 1.0,
            x: 0, y: 0, z: 0,
            spread: 0,
            lastMode: "car"
        };
    }
    return inp.spatState[n];
}

function parseSPATInput(inp, address, value) {
    const m = address.match(/^\/source\/(\d+)\/(\w+)$/);
    if (!m) return null;

    const n = parseInt(m[1]);
    const param = m[2];
    const s = getSpatSource(inp, n);

    if (!value) return null;

    switch (param) {
    case "aed":
        if (value.length < 3) return null;
        s.azim = value[0]; s.elev = value[1]; s.dist = value[2] / 100.0;
        s.lastMode = "pol";
        break;
    case "xyz":
        if (value.length < 3) return null;
        s.x = value[0]; s.y = value[1]; s.z = value[2];
        s.lastMode = "car";
        break;
    case "spread":
        if (value.length < 1) return null;
        // One figure on the wire, both extents internally.
        s.spread = value[0] / 100.0;
        // Spread alone doesn't switch coordinate mode.
        break;
    default:
        // mode/gain/mute and the rest have no equivalent in our model.
        return null;
    }

    if (s.lastMode === "pol") {
        return {
            command: "deg",
            sourceIndex: n,
            args: [s.azim, s.elev, s.dist, s.spread, s.spread]
        };
    }
    return {
        command: "car",
        sourceIndex: n,
        args: [s.x, s.y, s.z, s.spread, s.spread]
    };
}

function mapMessage(command, idx, args, outputType, norm) {
    switch (outputType) {
    case "SpatGRIS":       return mapForSpatGRIS(command, idx, args, norm);
    case "ADM-OSC":        return mapForADM(command, idx, args);
    case "SPAT Revolution": return mapForSPAT(command, idx, args);
    }
    return [];
}

// ----- SpatGRIS: pass /spat/serv through verbatim ------------------------ //
// The SpatGRIS server speaks /spat/serv natively, so we re-emit the
// command with the exact coordinate system we received. No lossy
// polar<->cartesian round-trip.
function mapForSpatGRIS(command, idx, args, norm) {
    // A legacy-form input goes back out in the legacy form, untouched.
    // idx is 1-based (+ any per-route offset); the legacy wire form is 0-based.
    if (norm && norm.legacyArgs) {
        return [{
            address: "/spat/serv",
            value: [idx - 1].concat(norm.legacyArgs)
        }];
    }
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
    // SpatGRIS speaks /spat/serv natively and supports commands we do not
    // model (e.g. "reset <id>", sg_OscInput.cpp:186-193). Forward anything we did
    // not recognise rather than dropping it on the floor.
    if (typeof command === "string" && command.length > 0) {
        return [{ address: "/spat/serv", value: [command, idx].concat(args) }];
    }
    return [];
}

// ----- ADM-OSC (v1.0) --------------------------------------------------- //
// Conventions:
//   - Azimuth: SpatGRIS uses −90° = left / +90° = right (example in spec:
//     "deg 7 -90.0 ... moves source #7 at the extreme left").
//     ADM uses +90° = left / −90° = right. → sign flipped.
//   - Elevation: both use 0° = horizon, +90° = above. → no change.
//   - Cartesian axes match: x = L/R, y = B/F, z = D/U with same signs.
// Ranges differ: SpatGRIS cartesian is the MBAP extended field
// (±MBAP_EXTENDED_RADIUS = ±1.6666667, sg_constants.hpp:71) while ADM-OSC
// cartesian is normalized ±1. Relying on the receiver to clamp (ADM-OSC §9)
// is NOT position-preserving: every source beyond 60% of full-scale collapses
// onto the wall, silently discarding the outer 40% of the field. We therefore
// scale the axes into ADM's normalized range. Polar radius is left alone: it
// is a distance, not a bounded axis, and ControlGris dome sources sit at ~1.
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

// SpatGRIS MBAP_EXTENDED_RADIUS (sg_constants.hpp:71) -- the cartesian clamp
// applied by CartesianVector::clampedToFarField (sg_CartesianVector.hpp:182-187).
const MBAP_EXTENDED_RADIUS = 1.6666667;

function cartesianToADM(idx, x, y, z, hspan) {
    const messages = [{
        address: `/adm/obj/${idx}/xyz`,
        value: [x / MBAP_EXTENDED_RADIUS,
                y / MBAP_EXTENDED_RADIUS,
                z / MBAP_EXTENDED_RADIUS]
    }];
    if (hspan !== undefined) {
        messages.push({ address: `/adm/obj/${idx}/w`, value: hspan });
    }
    return messages;
}

// ----- SPAT Revolution: /source/N/aed or /source/N/xyz ------------------- //
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

// ----- Input device lifecycle ------------------------------------------- //

function closeInput(inp) {
    if (inp.udp) {
        try { inp.udp.close(); } catch (e) {}
    }
    inp.udp = null;
    inp.osc = null;
    inp.listening = false;
}

function openInput(inp) {
    closeInput(inp);

    // Deferred so a socket being rebound on the same port has actually been
    // released before we bind again. Each closure captures its own device;
    // nothing here touches shared state.
    Qt.callLater(function () {
        inp.osc = Protocols.osc({
            onOsc: function (a, v) {
                onInputValueReceived(inp, a, v);
            }
        });
        inp.udp = Protocols.inboundUDP({
            Transport: {
                Bind: "0.0.0.0",
                Port: inp.port
            },
            onMessage: function (bytes) {
                inp.osc.processMessage(bytes);
            }
        });

        if (inp.udp) {
            inp.listening = true;
            inp.error = "";
        } else {
            inp.listening = false;
            inp.error = "Failed to open port " + inp.port + " (already in use?)";
        }
        updateInputList();
    });
}

// Two inputs cannot share a port; the second bind fails at the OS level and
// the app would show a listening device that never receives anything.
function portInUse(port, exceptId) {
    for (let i of inputs)
        if (i.port === port && i.id !== exceptId) return true;
    return false;
}

function createInput(name, port, protocol) {
    const inp = {
        id: nextId(),
        name: name,
        protocol: protocol || "Auto",
        port: port,
        enabled: true,     // what the user asked for; persisted
        listening: false,  // what the socket managed; runtime only
        scaleX: 1, scaleY: 1, scaleZ: 1,
        error: "",
        udp: null,
        osc: null,
        admState: {}
    };
    inputs.push(inp);
    openInput(inp);
    updateInputList();
    return inp;
}

function removeInput(id) {
    for (let i = 0; i < inputs.length; i++) {
        if (inputs[i].id !== id) continue;
        closeInput(inputs[i]);
        inputs.splice(i, 1);
        // Drop the routes that hung off it, or reindexRoutes would keep
        // dispatching through a device that no longer exists.
        routes = routes.filter(function (r) { return r.inputId !== id; });
        reindexRoutes();
        updateInputList();
        saveConfiguration();
        return;
    }
}

function updateInput(id, props) {
    const inp = findInput(id);
    if (!inp) return;

    if (props.name !== undefined) inp.name = props.name;
    if (props.protocol !== undefined && props.protocol !== inp.protocol) {
        inp.protocol = props.protocol;
        // The accumulated coordinates describe the previous reading.
        inp.admState = {};
        inp.spatState = {};
    }
    for (let axis of ["scaleX", "scaleY", "scaleZ"]) {
        if (props[axis] === undefined) continue;
        const v = parseFloat(props[axis]);
        if (!isNaN(v)) inp[axis] = v;
    }
    if (props.port !== undefined) {
        // The field hands back a string; a socket wants a number.
        const port = parsePort(props.port);
        // Refuse a port another input already holds: the bind would fail at
        // the OS level and leave a device that looks live but never receives.
        if (port !== null && port !== inp.port && !portInUse(port, id)) {
            inp.port = port;
            if (inp.enabled) openInput(inp);
        }
    }

    updateInputList();
    saveConfiguration();
}

// null when the text is not a usable port, so callers can keep what they had.
function parsePort(value) {
    const n = parseInt(value);
    return (isNaN(n) || n < 1 || n > 65535) ? null : n;
}

function setInputPort(id, port) {
    const inp = findInput(id);
    if (!inp || inp.port === port) return;
    inp.port = port;
    // Changing the port always rebinds; an input the user has switched off
    // stays off until they ask for it.
    if (inp.enabled) openInput(inp);
    else updateInputList();
    saveConfiguration();
}

function setInputProtocol(id, protocol) {
    const inp = findInput(id);
    if (!inp) return;
    inp.protocol = protocol;
    // The accumulated coordinates describe the old interpretation.
    inp.admState = {};
    inp.spatState = {};
    updateInputList();
    saveConfiguration();
}

function setInputName(id, name) {
    const inp = findInput(id);
    if (!inp) return;
    inp.name = name;
    updateInputList();
    saveConfiguration();
}

function setInputListening(id, listening) {
    const inp = findInput(id);
    if (!inp) return;
    inp.enabled = listening;
    if (listening) {
        openInput(inp);
    } else {
        closeInput(inp);
        inp.error = "";
        updateInputList();
    }
    saveConfiguration();
}

// ----- Output device lifecycle ------------------------------------------ //
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

function createOutput(name, host, port, protocol) {
    const dev = {
        id: nextId(),
        name: name,
        host: host,
        port: port,
        protocol: protocol,
        udp: null
    };
    openOutputSocket(dev);
    outputs.push(dev);
    updateOutputList();
    return dev;
}

// Fields are edited directly in the list; host and port changes have to
// reopen the socket, the rest are labels.
function updateOutput(id, props) {
    const out = findOutput(id);
    if (!out) return;

    let rebind = false;
    if (props.name !== undefined) out.name = props.name;
    if (props.protocol !== undefined) out.protocol = props.protocol;
    if (props.host !== undefined && props.host !== out.host) {
        out.host = props.host;
        rebind = true;
    }
    if (props.port !== undefined) {
        const port = parsePort(props.port);
        if (port !== null && port !== out.port) {
            out.port = port;
            rebind = true;
        }
    }

    if (rebind) openOutputSocket(out);
    updateOutputList();
    saveConfiguration();
}

function removeOutput(id) {
    for (let i = 0; i < outputs.length; i++) {
        if (outputs[i].id !== id) continue;
        const dev = outputs[i];
        if (dev.udp) {
            try { dev.udp.close(); } catch (e) {}
            dev.udp = null;
        }
        outputs.splice(i, 1);
        routes = routes.filter(function (r) { return r.outputId !== id; });
        reindexRoutes();
        updateOutputList();
        saveConfiguration();
        return;
    }
}

// ----- Routes ------------------------------------------------------------ //

function setRoute(inputId, outputId, props) {
    let r = findRoute(inputId, outputId);
    if (!r) {
        r = {
            inputId: inputId,
            outputId: outputId,
            enabled: true,
            sourceOffset: 0,
            srcMin: null,
            srcMax: null
        };
        routes.push(r);
    }
    if (props) {
        if (props.enabled !== undefined) r.enabled = props.enabled;
        if (props.sourceOffset !== undefined) r.sourceOffset = props.sourceOffset;
        if (props.srcMin !== undefined) r.srcMin = props.srcMin;
        if (props.srcMax !== undefined) r.srcMax = props.srcMax;
    }
    reindexRoutes();
    return r;
}

// Row-major (one input at a time), which is the order the matrix grid lays
// its cells out in.
function updateMatrixList() {
    const rows = [];
    for (let inp of inputs) {
        for (let out of outputs) {
            const r = findRoute(inp.id, out.id);
            rows.push({
                inputId: inp.id,
                outputId: out.id,
                routed: r ? r.enabled : false,
                sourceOffset: r ? (r.sourceOffset || 0) : 0,
                srcMin: (r && r.srcMin !== null && r.srcMin !== undefined) ? r.srcMin : -1,
                srcMax: (r && r.srcMax !== null && r.srcMax !== undefined) ? r.srcMax : -1
            });
        }
    }
    syncModel(matrixModel, rows, ["inputId", "outputId"]);
}

// ----- List models ------------------------------------------------------- //
// The engine keeps plain JS arrays; the views bind to these.

// Rebuilding a ListModel destroys every delegate: the matrix would flicker on
// each click, lose hover, and reset its scroll position. Patch in place while
// the rows still describe the same things, and only rebuild when the shape
// actually changed.
function syncModel(model, rows, identity) {
    let sameShape = (model.count === rows.length);
    if (sameShape) {
        for (let i = 0; i < rows.length && sameShape; i++) {
            const cur = model.get(i);
            for (let k of identity) {
                if (cur[k] !== rows[i][k]) { sameShape = false; break; }
            }
        }
    }

    if (!sameShape) {
        model.clear();
        for (let r of rows)
            model.append(r);
        return;
    }

    for (let i = 0; i < rows.length; i++) {
        const cur = model.get(i);
        for (let k in rows[i]) {
            if (cur[k] !== rows[i][k])
                model.setProperty(i, k, rows[i][k]);
        }
    }
}

function updateInputList() {
    const rows = [];
    for (let inp of inputs) {
        rows.push({
            inputId: inp.id,
            name: inp.name,
            protocol: inp.protocol,
            port: inp.port,
            enabled: inp.enabled !== false,
            listening: inp.listening,
            error: inp.error,
            scaleX: scaleOf(inp, "scaleX"),
            scaleY: scaleOf(inp, "scaleY"),
            scaleZ: scaleOf(inp, "scaleZ")
        });
    }
    syncModel(inputListModel, rows, ["inputId"]);
    // openInput() binds through Qt.callLater, so the listening flag settles
    // after the call that requested it; the window mirrors it from here.
    syncCurrentInput();
}

function updateOutputList() {
    const rows = [];
    for (let out of outputs) {
        // Only display fields — the `udp` socket is a QObject and doesn't
        // belong in a ListModel.
        rows.push({
            outputId: out.id,
            name: out.name,
            host: out.host,
            port: out.port,
            protocol: out.protocol
        });
    }
    syncModel(outputListModel, rows, ["outputId"]);
}

// One row per output, describing this input's route to it. ListModel cannot
// carry null, so an unbounded range is -1.
function updateRouteList(inputId) {
    const rows = [];
    for (let out of outputs) {
        const r = findRoute(inputId, out.id);
        rows.push({
            outputId: out.id,
            name: out.name,
            host: out.host,
            port: out.port,
            protocol: out.protocol,
            routed: r ? r.enabled : false,
            sourceOffset: r ? (r.sourceOffset || 0) : 0,
            srcMin: (r && r.srcMin !== null && r.srcMin !== undefined) ? r.srcMin : -1,
            srcMax: (r && r.srcMax !== null && r.srcMax !== undefined) ? r.srcMax : -1
        });
    }
    syncModel(routeListModel, rows, ["outputId"]);
}

// ----- Persistence ------------------------------------------------------- //

function saveConfiguration() {
    appSettings.savedConfiguration = JSON.stringify({
        version: 2,
        inputs: inputs.map(function (i) {
            return { id: i.id, name: i.name, protocol: i.protocol,
                     port: i.port, enabled: i.enabled !== false,
                     scaleX: scaleOf(i, "scaleX"),
                     scaleY: scaleOf(i, "scaleY"),
                     scaleZ: scaleOf(i, "scaleZ") };
        }),
        outputs: outputs.map(function (o) {
            return { id: o.id, name: o.name, protocol: o.protocol,
                     host: o.host, port: o.port };
        }),
        routes: routes.map(function (r) {
            return { inputId: r.inputId, outputId: r.outputId, enabled: r.enabled,
                     sourceOffset: r.sourceOffset || 0,
                     srcMin: (r.srcMin === undefined) ? null : r.srcMin,
                     srcMax: (r.srcMax === undefined) ? null : r.srcMax };
        })
    });
}

function restoreConfiguration() {
    let cfg = null;
    try {
        cfg = JSON.parse(appSettings.savedConfiguration || "null");
    } catch (e) {
        console.log("Could not parse saved configuration:", e);
    }

    if (cfg && cfg.version === 2 && cfg.inputs && cfg.inputs.length > 0)
        restoreV2(cfg);
    else
        migrateFromV1();

    reindexRoutes();
    updateInputList();
    updateOutputList();
}

function restoreV2(cfg) {
    let maxId = 0;
    for (let si of cfg.inputs) maxId = Math.max(maxId, si.id);
    for (let so of cfg.outputs || []) maxId = Math.max(maxId, so.id);
    g_nextId = maxId + 1;

    for (let si of cfg.inputs) {
        const inp = {
            id: si.id, name: si.name, protocol: si.protocol || "Auto",
            port: si.port, enabled: si.enabled !== false,
            scaleX: (si.scaleX === undefined) ? 1 : si.scaleX,
            scaleY: (si.scaleY === undefined) ? 1 : si.scaleY,
            scaleZ: (si.scaleZ === undefined) ? 1 : si.scaleZ,
            listening: false, error: "",
            udp: null, osc: null, admState: {}
        };
        inputs.push(inp);
        if (inp.enabled)
            openInput(inp);
    }

    for (let so of cfg.outputs || []) {
        const dev = {
            id: so.id, name: so.name, host: so.host,
            port: so.port, protocol: so.protocol, udp: null
        };
        openOutputSocket(dev);
        outputs.push(dev);
    }

    for (let sr of cfg.routes || []) {
        routes.push({
            inputId: sr.inputId,
            outputId: sr.outputId,
            enabled: sr.enabled !== false,
            sourceOffset: sr.sourceOffset || 0,
            srcMin: (sr.srcMin === undefined) ? null : sr.srcMin,
            srcMax: (sr.srcMax === undefined) ? null : sr.srcMax
        });
    }
}

// v1 was a single implicit input plus a flat list of outputs, each carrying
// its own offset and an `active` flag, with every output fed from that input.
// That maps exactly onto one input and one route per output. The v1 keys are
// left in place rather than deleted — they cost nothing and a user who rolls
// back keeps their setup.
function migrateFromV1() {
    const inp = createInput("Input 1", appSettings.listenPort, "Auto");

    let saved = [];
    try {
        saved = JSON.parse(appSettings.savedOutputDevices || "[]");
    } catch (e) {
        console.log("Could not restore saved outputs:", e);
    }

    for (let o of saved) {
        const dev = createOutput(o.name, o.host, o.port, o.type);
        setRoute(inp.id, dev.id, {
            enabled: o.active !== false,
            sourceOffset: o.sourceIndexOffset || 0,
            srcMin: null,
            srcMax: null
        });
    }

    saveConfiguration();
}

// ----- Log drain --------------------------------------------------------- //

var VIEW_MAX_LINES = 1000;
var FLUSH_HZ = 60;
var g_drainBudget = 0;

function flushLogs() {
    var perTick = appSettings.monitorMaxRate / FLUSH_HZ;
    // Floor cap at 1: low rates have perTick < 0.5 so 2*perTick would never
    // reach a whole line and Math.floor(budget) would stick at 0.
    var cap = Math.max(1, perTick * 2);
    g_drainBudget = Math.min(g_drainBudget + perTick, cap);

    if (!LogQueue.hasWork()) return;

    var n = Math.floor(g_drainBudget);
    if (n <= 0) return;

    var lines = LogQueue.drainUpTo(n);
    if (lines.length === 0) return;
    g_drainBudget -= lines.length;

    messageMonitor.append(lines.join('\n'));

    var excess = messageMonitor.lineCount - VIEW_MAX_LINES;
    if (excess > 0) {
        var t = messageMonitor.text;
        var idx = -1;
        for (var j = 0; j < excess; j++) {
            idx = t.indexOf('\n', idx + 1);
            if (idx < 0) break;
        }
        if (idx >= 0) messageMonitor.remove(0, idx + 1);
    }
}

function clearLogs() {
    LogQueue.clear();
    g_drainBudget = 0;
    messageMonitor.clear();
}
