.import "../qml/spm/Engine.js" as Engine
.import "../qml/spm/Handlers.js" as Handlers
.import "../qml/spm/handlers/Spm.js" as Spm

// The parse/map functions Engine.js had before protocols became handlers,
// rebuilt on top of the handlers and the engine's own address resolution.
//
// tst_engine.qml pinned the wire output of every protocol path through these
// signatures. Keeping them lets the same assertions run, unchanged, against
// the handler implementation: if a handler drifts, those tests fail.
//
//   norm: { command: "pol" | "deg" | "car" | "clr" | "alg" | <other>,
//           sourceIndex, args, legacyArgs? }

// ----- Event <-> command form -------------------------------------------- //

function toLegacy(ev) {
    let n = null;
    switch (ev.type) {
    case Spm.POSITION:
        if (ev.coords === Spm.CARTESIAN) {
            n = { command: "car", args: [ev.x, ev.y, ev.z, ev.hspan, ev.vspan] };
        } else if (ev.radians) {
            n = { command: "pol", args: [ev.azimuth * Spm.RAD, ev.elevation * Spm.RAD,
                                         ev.distance, ev.hspan, ev.vspan] };
        } else {
            n = { command: "deg", args: [ev.azimuth, ev.elevation, ev.distance, ev.hspan, ev.vspan] };
        }
        if (ev.nativeProtocol === "SpatGRIS" && typeof ev.nativeArgs[0] === "number")
            n.legacyArgs = ev.nativeArgs.slice(1);
        break;
    case Spm.CLEAR:
        n = { command: "clr", args: [] };
        break;
    case Spm.ALGORITHM:
        n = { command: "alg", args: ev.value === null ? [] : [ev.value] };
        break;
    case Spm.NATIVE:
        // Only SpatGRIS used to parse a command it did not model.
        if (ev.nativeProtocol !== "SpatGRIS") return null;
        n = { command: ev.nativeArgs[0], args: ev.nativeArgs.slice(2) };
        break;
    default:
        return null;
    }
    n.sourceIndex = ev.source;
    return n;
}

function fromLegacy(command, idx, args, norm) {
    const ev = Spm.newEvent();
    ev.source = idx;
    switch (command) {
    case "pol":
    case "deg":
        if (args.length < 5) return null;
        ev.type = Spm.POSITION;
        ev.coords = Spm.SPHERICAL;
        ev.radians = (command === "pol");
        ev.azimuth = ev.radians ? args[0] * Spm.DEG : args[0];
        ev.elevation = ev.radians ? args[1] * Spm.DEG : args[1];
        ev.distance = args[2];
        ev.hspan = args[3];
        ev.vspan = args[4];
        break;
    case "car":
        if (args.length < 5) return null;
        ev.type = Spm.POSITION;
        ev.coords = Spm.CARTESIAN;
        ev.x = args[0]; ev.y = args[1]; ev.z = args[2];
        ev.hspan = args[3];
        ev.vspan = args[4];
        break;
    case "clr":
        ev.type = Spm.CLEAR;
        break;
    case "alg":
        ev.type = Spm.ALGORITHM;
        ev.value = args.length > 0 ? args[0] : null;
        break;
    default:
        ev.type = Spm.NATIVE;
        ev.nativeProtocol = "SpatGRIS";
        ev.nativeAddress = "/spat/serv";
        ev.nativeArgs = [command, idx].concat(args);
    }
    if (norm && norm.legacyArgs && ev.type === Spm.POSITION) {
        ev.nativeProtocol = "SpatGRIS";
        ev.nativeAddress = "/spat/serv";
        ev.nativeArgs = [norm.sourceIndex - 1].concat(norm.legacyArgs);
    }
    return ev;
}

// ----- Parsing ----------------------------------------------------------- //

// The runtime for one protocol on one test input. The handlers keep their
// accumulators per instance, so a fresh input object means fresh state.
function runtimeFor(inp, protocol) {
    if (!inp.__legacy) inp.__legacy = {};
    let shadow = inp.__legacy[protocol];
    if (!shadow) {
        shadow = { id: inp.id, name: inp.name, protocol: protocol, params: {}, rt: null };
        inp.__legacy[protocol] = shadow;
    }
    return shadow.rt || Engine.attachInput(shadow);
}

function decodeWith(rt, address, value) {
    let e = rt.cache.get(address);
    if (e === undefined) e = Engine.resolveAddress(rt, address);
    Engine.resetEvent(rt.ev);
    if (e.fn === null) return null;
    return e.fn(e.n, value, rt.ev, address) === true ? toLegacy(rt.ev) : null;
}

function parseSpatGRISInput(value) {
    return decodeWith(runtimeFor({ id: 0, name: "legacy" }, "SpatGRIS"), "/spat/serv", value);
}

function parseADMInput(inp, address, value) {
    return decodeWith(runtimeFor(inp, "ADM-OSC"), address, value);
}

function parseSPATInput(inp, address, value) {
    return decodeWith(runtimeFor(inp, "SPAT Revolution"), address, value);
}

// The input's own protocol, "Auto" included, resolved exactly as the engine does.
function parseInput(inp, address, value) {
    return decodeWith(runtimeFor(inp, inp.protocol || "Auto"), address, value);
}

// ----- Scaling ----------------------------------------------------------- //

// Returns the message unchanged when the scale is identity or it carries no
// position.
function applyInputScale(inp, norm) {
    if (!norm || !Engine.inputHasScale(inp)) return norm;
    if (norm.command !== "pol" && norm.command !== "deg" && norm.command !== "car") return norm;
    const ev = fromLegacy(norm.command, norm.sourceIndex, norm.args, norm);
    if (ev === null) return norm;
    Spm.scaleEvent(ev, Engine.scaleOf(inp, "scaleX"), Engine.scaleOf(inp, "scaleY"),
                   Engine.scaleOf(inp, "scaleZ"));
    return toLegacy(ev);
}

// ----- Mapping ----------------------------------------------------------- //

// What an output of that protocol sends for the message, as
// [{ address, value }]. Values are copied: encoders reuse their buffers.
function mapMessage(command, idx, args, outputType, norm) {
    const h = Handlers.get(outputType);
    if (h === null || !h.hasOutput) return [];

    const sent = [];
    const enc = h.descriptor.createOutput({
        device: { id: 0, name: "legacy" },
        params: Handlers.resolveParams(h, null),
        send: function (address, values) {
            sent.push({ address: address, value: Array.isArray(values) ? values.slice() : [values] });
        },
        log: function () {},
        error: function () {}
    });

    const ev = fromLegacy(command, idx, args, norm);
    if (ev === null) return [];
    switch (ev.type) {
    case Spm.POSITION:  if (enc.position) enc.position(ev); break;
    case Spm.CLEAR:     if (enc.clear) enc.clear(ev); break;
    case Spm.ALGORITHM: if (enc.algorithm) enc.algorithm(ev); break;
    case Spm.NATIVE:    if (enc.native) enc.native(ev); break;
    }
    return sent;
}

function mapForSpatGRIS(command, idx, args, norm) {
    return mapMessage(command, idx, args, "SpatGRIS", norm);
}

function mapForADM(command, idx, args) {
    return mapMessage(command, idx, args, "ADM-OSC", null);
}

function mapForSPAT(command, idx, args) {
    return mapMessage(command, idx, args, "SPAT Revolution", null);
}
