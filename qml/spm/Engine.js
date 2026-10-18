.import "LogQueue.js" as LogQueue
.import "Handlers.js" as Handlers
.import "handlers/Spm.js" as Spm
.import "handlers/Template.js" as Template

// Routing engine.
//
// Any number of inputs and outputs, with an explicit route per connection.
//
//   inputs  [{ id, name, protocol, port, listening, error, params, udp, osc, rt }]
//   outputs [{ id, name, protocol, host, port, params, udp, rt }]
//   routes  [{ inputId, outputId, enabled, sourceOffset, srcMin, srcMax }]
//
// `srcMin`/`srcMax` are null when the route carries every source. The filter
// tests the *incoming* source index, before `sourceOffset` is applied, so the
// numbers in the UI match the numbers on the sender.
//
// Protocols are handlers (Handlers.js, docs/HANDLERS.md). Each device holds a
// runtime, `rt`, with its handler instance; it is built lazily and dropped
// whenever the protocol, its params or its script change.
//
// Free variables (inputs, outputs, routes, appSettings, the list models,
// messageMonitor, monitorActive, Protocols) resolve against Main.qml.

// Read once: module property lookups do not belong on the message path.
var POSITION = Spm.POSITION;
var CLEAR = Spm.CLEAR;
var ALGORITHM = Spm.ALGORITHM;
var NATIVE = Spm.NATIVE;

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

// ----- Logging ---------------------------------------------------------- //
// Formatting a log line costs more than the routing, so the message path only
// tests these. The window calls updateLogging() whenever an input to them
// changes.
var g_logIn = false;
var g_logOut = false;

function updateLogging() {
    g_logIn = !!(appSettings.logReceivedMessages && monitorActive);
    g_logOut = !!(appSettings.logSentMessages && monitorActive);
}

// ----- Dispatch index --------------------------------------------------- //
// Rebuilt on every structural change; the message path only reads it. Each
// link carries everything dispatch needs, so no lookup happens per message.
var g_linksByInput = {};

function reindexRoutes() {
    g_linksByInput = {};
    for (let r of routes) {
        if (!r.enabled) continue;
        const out = findOutput(r.outputId);
        if (!out) continue;

        let rt = out.rt;
        if (!rt || rt.protocol !== out.protocol)
            rt = attachOutput(out);
        const enc = rt.enc;

        if (!g_linksByInput[r.inputId])
            g_linksByInput[r.inputId] = [];
        g_linksByInput[r.inputId].push({
            route: r,
            output: out,
            entry: rt.entry,
            enc: enc,
            offset: r.sourceOffset || 0,
            min: (r.srcMin === null || r.srcMin === undefined) ? -Infinity : r.srcMin,
            max: (r.srcMax === null || r.srcMax === undefined) ? Infinity : r.srcMax,
            position: !!enc && typeof enc.position === "function",
            clear: !!enc && typeof enc.clear === "function",
            algorithm: !!enc && typeof enc.algorithm === "function",
            native: !!enc && typeof enc.native === "function"
        });
    }
}

// Messages with no source index (/adm/lis, /adm/env, global commands, anything
// forwarded verbatim) bypass the filter rather than being silenced by it.
function routeAccepts(route, sourceIndex) {
    if (sourceIndex < 0) return true;
    if (route.srcMin !== null && route.srcMin !== undefined && sourceIndex < route.srcMin)
        return false;
    if (route.srcMax !== null && route.srcMax !== undefined && sourceIndex > route.srcMax)
        return false;
    return true;
}

// ----- Message path ----------------------------------------------------- //
// Steady state allocates nothing here: the event is the input's own, the
// address resolves through a per-input cache, and encoders send from buffers
// they allocated once. Score's udp.osc() copies its arguments before
// returning (libossia protocols_sender::send_osc), which is what makes reusing
// those buffers safe.

var ADDRESS_CACHE_MAX = 4096;

function onInputValueReceived(inp, address, value) {
    if (g_logIn)
        LogQueue.pushInput(`IN  [${inp.name}] ${address} = ${JSON.stringify(value)}`);

    let rt = inp.rt;
    if (rt === undefined || rt === null)
        rt = attachInput(inp);

    let e = rt.cache.get(address);
    if (e === undefined)
        e = resolveAddress(rt, address);

    const ev = rt.ev;
    resetEvent(ev);
    rt.emitted = false;

    // Decoded unconditionally: ADM and SPAT accumulate one parameter per
    // message, and that state has to stay current even while nothing is routed.
    let decoded = false;
    if (e.fn !== null) {
        try {
            decoded = e.fn(e.n, value, ev, address) === true;
        } catch (err) {
            handlerThrew(inp, e.decoder.entry, err);
        }
    }

    const links = g_linksByInput[inp.id];
    if (links === undefined || links.length === 0) return;

    if (decoded && ev.type !== 0) {
        routeEvent(inp, links, ev);
        return;
    }
    if (rt.emitted) return;

    // Nothing understood it, but a protocol claims its address space: pass it
    // through verbatim to that protocol's outputs. This is how ADM gain, mute,
    // /adm/lis, /adm/env, … reach ADM-OSC outputs.
    if (e.nativeProtocol !== null) {
        ev.type = NATIVE;
        ev.source = e.nativeSource;
        ev.nativeProtocol = e.nativeProtocol;
        ev.nativeAddress = address;
        ev.nativeArgs = Array.isArray(value) ? value : [value];
        dispatch(links, ev);
    }
}

function resetEvent(ev) {
    ev.type = 0;
    ev.source = -1;
    ev.offset = 0;
    ev.coords = Spm.SPHERICAL;
    ev.radians = false;
    ev.azimuth = 0; ev.elevation = 0; ev.distance = 1;
    ev.x = 0; ev.y = 0; ev.z = 0;
    ev.hspan = 0; ev.vspan = 0;
    ev.value = null;
    ev.nativeProtocol = null;
    ev.nativeAddress = null;
    ev.nativeArgs = null;
}

// Per-input scaling, then every route.
function routeEvent(inp, links, ev) {
    if (ev.type === POSITION)
        Spm.scaleEvent(ev, scaleOf(inp, "scaleX"), scaleOf(inp, "scaleY"), scaleOf(inp, "scaleZ"));
    dispatch(links, ev);
}

function dispatch(links, ev) {
    const inSource = ev.source;
    const type = ev.type;
    for (let i = 0; i < links.length; i++) {
        const l = links[i];
        if (!l.output.udp) continue;
        if (inSource >= 0 && (inSource < l.min || inSource > l.max)) continue;

        ev.offset = l.offset;
        ev.source = inSource + l.offset;
        try {
            switch (type) {
            case POSITION:  if (l.position) l.enc.position(ev); break;
            case CLEAR:     if (l.clear) l.enc.clear(ev); break;
            case ALGORITHM: if (l.algorithm) l.enc.algorithm(ev); break;
            case NATIVE:    if (l.native) l.enc.native(ev); break;
            }
        } catch (err) {
            handlerThrew(l.output, l.entry, err);
        }
    }
    ev.source = inSource;
    ev.offset = 0;
}

// First sight of an address: which decoder function takes it, with which
// source index, and which protocol claims it if that decoder declines.
function resolveAddress(rt, address) {
    let fn = null, n = -1, decoder = null;
    for (let d of rt.decoders) {
        if (!address.startsWith(d.prefix)) continue;
        // The first decoder whose prefix matches owns the address, matched or not.
        decoder = d;
        for (let pt of d.patterns) {
            const m = Spm.matchPattern(pt.p, address);
            if (m !== -2) { fn = pt.fn; n = m; break; }
        }
        if (fn === null) fn = d.fallback;
        break;
    }

    let nativeProtocol = null, nativeSource = -1;
    for (let h of Handlers.all()) {
        if (h.native === null || !address.startsWith(h.native.prefix)) continue;
        nativeProtocol = h.id;
        if (typeof h.native.source === "function") {
            try {
                const s = h.native.source(address);
                nativeSource = (typeof s === "number" && s >= 0) ? s : -1;
            } catch (err) {
                nativeSource = -1;
            }
        }
        break;
    }

    const e = { fn: fn, n: n, decoder: decoder,
                nativeProtocol: nativeProtocol, nativeSource: nativeSource };
    // A sender spraying unique addresses must not grow this without bound.
    if (rt.cache.size >= ADDRESS_CACHE_MAX)
        rt.cache.clear();
    rt.cache.set(address, e);
    return e;
}

// ----- Handler runtimes ------------------------------------------------- //

// Inputs set to "Auto" run every decoder that declares an address prefix, in
// registration order; the first prefix that matches an address owns it.
function inputEntriesFor(protocol) {
    if (protocol === "Auto") {
        const list = [];
        for (let h of Handlers.all())
            if (h.hasInput && h.matches !== null) list.push(h);
        return list;
    }
    const h = Handlers.get(protocol);
    return (h !== null && h.hasInput) ? [h] : [];
}

function deviceInfo(dev) {
    return { id: dev.id, name: dev.name };
}

function makeInputContext(inp, rt, entry) {
    return {
        device: deviceInfo(inp),
        params: Handlers.resolveParams(entry, inp.protocol === "Auto" ? null : inp.params),
        // Routes the event as it stands now, for a decoder that produces more
        // than one per message (or produces one outside onMessage).
        emit: function () {
            const links = g_linksByInput[inp.id];
            rt.emitted = true;
            if (links === undefined || links.length === 0 || rt.ev.type === 0) return;
            routeEvent(inp, links, rt.ev);
        },
        log: function (msg) { console.log(`[${entry.id}] ${inp.name}:`, msg); },
        error: function (msg) { setHandlerError(inp, String(msg)); }
    };
}

function makeOutputContext(out, entry) {
    return {
        device: deviceInfo(out),
        params: Handlers.resolveParams(entry, out.params),
        send: function (address, args) {
            const u = out.udp;
            if (!u) return;
            if (!Array.isArray(args)) args = [args];
            u.osc(address, args);
            if (g_logOut)
                LogQueue.pushOutput(`OUT [${out.name}] ${address} = ${JSON.stringify(args.length === 1 ? args[0] : args)}`);
        },
        log: function (msg) { console.log(`[${entry.id}] ${out.name}:`, msg); },
        error: function (msg) { setHandlerError(out, String(msg)); }
    };
}

function attachInput(inp) {
    detachInput(inp);
    const rt = {
        protocol: inp.protocol,
        ev: Spm.newEvent(),
        cache: new Map(),
        decoders: [],
        emitted: false
    };
    inp.rt = rt;
    inp.handlerError = "";
    inp.handlerErrors = 0;

    for (let h of inputEntriesFor(inp.protocol)) {
        const ctx = makeInputContext(inp, rt, h);
        let table = null;
        try {
            table = h.descriptor.createInput(ctx);
        } catch (err) {
            handlerThrew(inp, h, err);
            continue;
        }
        if (!table || typeof table !== "object") continue;
        const c = Handlers.compileInputTable(table);
        rt.decoders.push({
            entry: h,
            prefix: h.matches || "",
            patterns: c.patterns,
            fallback: c.fallback,
            table: table,
            ctx: ctx
        });
    }
    return rt;
}

function detachInput(inp) {
    const rt = inp.rt;
    inp.rt = null;
    if (!rt) return;
    for (let d of rt.decoders)
        callDestroy(inp, d.entry, d.table);
}

function attachOutput(out) {
    detachOutput(out);
    const entry = Handlers.get(out.protocol);
    const rt = { protocol: out.protocol, entry: entry, enc: null, ctx: null };
    out.rt = rt;
    out.handlerError = "";
    out.handlerErrors = 0;
    if (entry === null || !entry.hasOutput) return rt;

    rt.ctx = makeOutputContext(out, entry);
    try {
        const enc = entry.descriptor.createOutput(rt.ctx);
        rt.enc = (enc && typeof enc === "object") ? enc : null;
    } catch (err) {
        handlerThrew(out, entry, err);
    }
    return rt;
}

function detachOutput(out) {
    const rt = out.rt;
    out.rt = null;
    if (rt && rt.enc)
        callDestroy(out, rt.entry, rt.enc);
}

function callDestroy(dev, entry, instance) {
    if (!instance || typeof instance.destroy !== "function") return;
    try {
        instance.destroy();
    } catch (err) {
        handlerThrew(dev, entry, err);
    }
}

// Reported once per distinct message; the console gets the first throw and
// then one line per thousand, so a handler failing on every message cannot
// flood it.
var ERROR_LOG_EVERY = 1000;

function handlerThrew(dev, entry, err) {
    dev.handlerErrors = (dev.handlerErrors || 0) + 1;
    const text = Handlers.describeError(err);
    if (dev.handlerErrors === 1 || dev.handlerErrors % ERROR_LOG_EVERY === 0)
        console.log(`Handler ${entry ? entry.id : "?"} on ${dev.name} threw (${dev.handlerErrors}x):`, text);
    setHandlerError(dev, "Handler error: " + text);
}

// The lists are rebuilt later, never from inside the message path.
var g_listUpdatePending = false;

function setHandlerError(dev, msg) {
    if (dev.handlerError === msg) return;
    dev.handlerError = msg;
    if (g_listUpdatePending) return;
    g_listUpdatePending = true;
    Qt.callLater(function () {
        g_listUpdatePending = false;
        updateInputList();
        updateOutputList();
    });
}

// What the device's row shows when the socket itself is fine.
function handlerStatus(dev, kind) {
    if (dev.handlerError) return dev.handlerError;
    if (kind === "input" && dev.protocol === "Auto") return "";
    const h = Handlers.get(dev.protocol);
    if (h === null) return "Handler not loaded: " + dev.protocol;
    if (kind === "input" && !h.hasInput) return h.name + " has no input side";
    if (kind === "output" && !h.hasOutput) return h.name + " has no output side";
    return "";
}

// A script was loaded, reloaded or removed. Devices on that protocol get a new
// instance; everyone's address cache goes, since a protocol may have claimed
// or released an address space.
function handlersChanged(id) {
    for (let inp of inputs) {
        if (inp.protocol === id || inp.protocol === "Auto")
            detachInput(inp);
        else if (inp.rt)
            inp.rt.cache.clear();
    }
    for (let out of outputs)
        if (out.protocol === id)
            detachOutput(out);
    reindexRoutes();
}

// ----- Params ------------------------------------------------------------ //

function paramSpecs(protocol) {
    const h = Handlers.get(protocol);
    return h === null ? [] : h.params;
}

function hasParams(dev) {
    return dev.protocol !== "Auto" && paramSpecs(dev.protocol).length > 0;
}

// The values the device's handler runs with, defaults filled in.
function paramValues(dev) {
    return Handlers.resolveParams(Handlers.get(dev.protocol), dev.params);
}

// Updates the live instance in place when it can take it (onParamsChanged),
// and rebuilds it otherwise.
function setDeviceParams(dev, values, kind) {
    const h = Handlers.get(dev.protocol);
    dev.params = Handlers.resolveParams(h, values);

    const instances = [];
    if (kind === "input" && dev.rt) {
        for (let d of dev.rt.decoders) instances.push({ ctx: d.ctx, obj: d.table });
    } else if (kind === "output" && dev.rt && dev.rt.ctx) {
        instances.push({ ctx: dev.rt.ctx, obj: dev.rt.enc });
    }

    let rebuild = instances.length === 0;
    for (let it of instances) {
        if (!it.obj || typeof it.obj.onParamsChanged !== "function") { rebuild = true; break; }
    }

    if (!rebuild) {
        for (let it of instances) {
            const p = it.ctx.params;
            for (let k in dev.params) p[k] = dev.params[k];
            try {
                it.obj.onParamsChanged();
            } catch (err) {
                handlerThrew(dev, h, err);
            }
        }
    } else if (kind === "input") {
        detachInput(dev);
    } else {
        attachOutput(dev);
        reindexRoutes();
    }
}

// ----- Per-input scaling ------------------------------------------------ //
// A negative factor mirrors that axis. Applied to the event before any route
// sees it (Spm.scaleEvent).

function scaleOf(inp, axis) {
    const v = inp[axis];
    return (v === undefined || v === null) ? 1 : v;
}

function inputHasScale(inp) {
    return scaleOf(inp, "scaleX") !== 1
        || scaleOf(inp, "scaleY") !== 1
        || scaleOf(inp, "scaleZ") !== 1;
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

    // Deferred so a socket rebound on the same port has been released first.
    Qt.callLater(function () {
        // A pending callLater cannot be cancelled, so re-check that the device
        // still exists, is still wanted, and has not already been bound.
        if (inputs.indexOf(inp) < 0) return;
        if (!inp.enabled) return;
        if (inp.udp) return;

        try {
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
                    // The socket can outlive the parser on teardown.
                    if (inp.osc) inp.osc.processMessage(bytes);
                }
            });
        } catch (e) {
            console.log("Failed to listen on", inp.port, e);
            inp.udp = null;
        }

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

// The second bind on a shared port fails at the OS level.
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
        params: {},
        error: "",
        udp: null,
        osc: null,
        rt: null
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
        detachInput(inputs[i]);
        inputs.splice(i, 1);
        // Routes referencing it would keep resolving.
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

    if (props.name !== undefined) {
        inp.name = props.name;
        if (inp.rt)
            for (let d of inp.rt.decoders) d.ctx.device.name = inp.name;
    }
    if (props.protocol !== undefined && props.protocol !== inp.protocol) {
        inp.protocol = props.protocol;
        // The accumulated coordinates describe the previous reading, and the
        // params belong to the previous handler.
        inp.params = {};
        detachInput(inp);
    }
    for (let axis of ["scaleX", "scaleY", "scaleZ"]) {
        if (props[axis] === undefined) continue;
        const v = parseFloat(props[axis]);
        if (!isNaN(v)) inp[axis] = v;
    }
    if (props.port !== undefined) {
        // The field hands back a string; a socket wants a number.
        const port = parsePort(props.port);
        if (port === null) {
            inp.error = "Invalid port";
        } else if (port !== inp.port) {
            // Two inputs on one port: the second bind fails at the OS level.
            if (portInUse(port, id)) {
                inp.error = "Port " + port + " is already used by another input";
            } else {
                inp.error = "";
                inp.port = port;
                if (inp.enabled) openInput(inp);
            }
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
// Each output device is backed by a raw outbound UDP socket. Its handler
// formats OSC in JS and sends through udp.osc(addr, values).
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
        params: {},
        udp: null,
        rt: null
    };
    openOutputSocket(dev);
    outputs.push(dev);
    updateOutputList();
    return dev;
}

// Host and port changes reopen the socket; a protocol change rebuilds the
// handler; the rest are labels.
function updateOutput(id, props) {
    const out = findOutput(id);
    if (!out) return;

    let rebind = false;
    if (props.name !== undefined) {
        out.name = props.name;
        if (out.rt && out.rt.ctx) out.rt.ctx.device.name = out.name;
    }
    if (props.protocol !== undefined && props.protocol !== out.protocol) {
        out.protocol = props.protocol;
        out.params = {};
        detachOutput(out);
        reindexRoutes();
    }
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
        detachOutput(dev);
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

// Row-major, matching the order the matrix grid lays its cells out in.
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

// ----- Protocol menus ---------------------------------------------------- //

function protocolName(id) {
    if (id === "Auto") return "Auto";
    const h = Handlers.get(id);
    return h === null ? id + " (not loaded)" : h.name;
}

// Parallel id and name lists for a protocol picker. A protocol some device
// uses but no script provides any more stays listed, so the picker can show it.
function protocolOptions(kind) {
    const ids = [];
    const names = [];
    if (kind === "input") { ids.push("Auto"); names.push("Auto"); }
    for (let h of Handlers.all()) {
        if (kind === "input" ? !h.hasInput : !h.hasOutput) continue;
        ids.push(h.id);
        names.push(h.name);
    }
    for (let d of (kind === "input" ? inputs : outputs)) {
        if (ids.indexOf(d.protocol) >= 0) continue;
        ids.push(d.protocol);
        names.push(protocolName(d.protocol));
    }
    return { ids: ids, names: names };
}

// [{ id, name }] of the protocols an output can be added with.
function outputChoices(builtin) {
    const list = [];
    for (let h of Handlers.all())
        if (h.hasOutput && h.builtin === builtin) list.push({ id: h.id, name: h.name });
    return list;
}

function defaultPortFor(protocol) {
    const h = Handlers.get(protocol);
    return h === null ? 8000 : h.defaultPort;
}

// ----- List models ------------------------------------------------------- //
// The engine keeps plain JS arrays; the views bind to these.

// Rebuilding a ListModel destroys every delegate, losing hover and scroll
// position. Patch in place while the row identities hold.
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
            // A socket problem first: without it nothing arrives at all.
            error: inp.error ? inp.error : handlerStatus(inp, "input"),
            hasParams: hasParams(inp),
            scaleX: scaleOf(inp, "scaleX"),
            scaleY: scaleOf(inp, "scaleY"),
            scaleZ: scaleOf(inp, "scaleZ")
        });
    }
    syncModel(inputListModel, rows, ["inputId"]);
    // openInput() binds through Qt.callLater, so the flag settles after the
    // call that requested it.
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
            protocol: out.protocol,
            protocolName: protocolName(out.protocol),
            error: handlerStatus(out, "output"),
            hasParams: hasParams(out)
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
            error: handlerStatus(out, "output"),
            hasParams: hasParams(out),
            routed: r ? r.enabled : false,
            sourceOffset: r ? (r.sourceOffset || 0) : 0,
            srcMin: (r && r.srcMin !== null && r.srcMin !== undefined) ? r.srcMin : -1,
            srcMax: (r && r.srcMax !== null && r.srcMax !== undefined) ? r.srcMax : -1
        });
    }
    syncModel(routeListModel, rows, ["outputId"]);
}

// ----- Handler scripts --------------------------------------------------- //
// Two kinds, both listed by URL in appSettings.handlerScripts:
//   - files ("file:///…"), read and written with XMLHttpRequest, which needs
//     QML_XHR_ALLOW_FILE_READ=1 and QML_XHR_ALLOW_FILE_WRITE=1 (`environment`);
//   - inline scripts ("inline:<name>"), written in the app's editor, whose
//     source is kept in appSettings.inlineScripts. These need no file access,
//     so they also work where there is none (wasm).
// Loading is asynchronous for files: a device on a protocol that is not loaded
// yet keeps its settings and picks the handler up when it arrives.

var INLINE = "inline:";

function isInline(url) {
    return url.startsWith(INLINE);
}

function savedScriptUrls() {
    if (appSettings.handlerScripts === undefined) return [];
    try {
        const list = JSON.parse(appSettings.handlerScripts || "[]");
        return Array.isArray(list) ? list.filter(function (u) { return typeof u === "string"; }) : [];
    } catch (e) {
        console.log("Could not parse the saved handler scripts:", e);
        return [];
    }
}

function saveScriptUrls() {
    if (appSettings.handlerScripts === undefined) return;
    appSettings.handlerScripts = JSON.stringify(Handlers.scripts().map(function (s) { return s.url; }));
}

// url -> source, for inline scripts.
function inlineSources() {
    if (appSettings.inlineScripts === undefined) return {};
    try {
        const m = JSON.parse(appSettings.inlineScripts || "{}");
        return (m && typeof m === "object" && !Array.isArray(m)) ? m : {};
    } catch (e) {
        console.log("Could not parse the saved inline scripts:", e);
        return {};
    }
}

function saveInlineSource(url, source) {
    if (appSettings.inlineScripts === undefined) return;
    const m = inlineSources();
    if (source === null) delete m[url];
    else m[url] = source;
    appSettings.inlineScripts = JSON.stringify(m);
}

function loadSavedScripts() {
    const inline = inlineSources();
    for (let url of savedScriptUrls()) {
        if (isInline(url))
            registerSource(url, inline.hasOwnProperty(url) ? inline[url] : "",
                           inline.hasOwnProperty(url) ? "" : "The script's source is missing");
        else
            readScript(url);
    }
}

function scriptRecord(url) {
    for (let s of Handlers.scripts())
        if (s.url === url) return s;
    return null;
}

// Compiles `source` for `url` (or records `readError`), then brings the
// devices and lists up to date. Returns the error, or "".
function registerSource(url, source, readError) {
    const before = scriptRecord(url);
    const previousId = before ? before.id : "";

    let err = readError;
    if (err === "")
        err = Handlers.loadScript(url, source);
    else
        Handlers.scriptFailed(url, err);
    if (err !== "")
        console.log("Handler script", url, "failed:", err);

    const after = scriptRecord(url);
    if (previousId !== "" && previousId !== (after ? after.id : ""))
        handlersChanged(previousId);
    if (after && after.id !== "")
        handlersChanged(after.id);

    updateHandlerList();
    // The window's refresh() also rebuilds the protocol pickers.
    if (typeof refresh === "function") {
        refresh();
    } else {
        updateInputList();
        updateOutputList();
    }
    return err;
}

// file:// requests that Qt does not allow (QML_XHR_ALLOW_FILE_READ/WRITE unset)
// never complete; they only print a warning. Give up on them after this long.
var FILE_TIMEOUT_MS = 2000;

function after(ms, fn) {
    const t = Qt.createQmlObject("import QtQml; Timer { repeat: false }", appSettings);
    t.interval = ms;
    t.triggered.connect(function () { t.destroy(); fn(); });
    t.start();
}

// `done(text, error)`, exactly once.
function fileRequest(method, url, body, done) {
    let settled = false;
    const finish = function (text, error) {
        if (settled) return;
        settled = true;
        done(text, error);
    };
    let xhr;
    try {
        xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            // Qt throws on `status` before the request is done.
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            // file:// reports status 0 on success.
            if (xhr.status === 0 || xhr.status === 200) finish(xhr.responseText, "");
            else finish("", "status " + xhr.status);
        };
        xhr.open(method, url);
        xhr.send(body);
    } catch (e) {
        finish("", String(e));
        return;
    }
    after(FILE_TIMEOUT_MS, function () {
        if (settled) return;
        // Before abort(): it fires DONE with status 0, which reads as success.
        finish("", method === "PUT" ? "file writes are not allowed (QML_XHR_ALLOW_FILE_WRITE=1)"
                                    : "file reads are not allowed (QML_XHR_ALLOW_FILE_READ=1)");
        try { xhr.abort(); } catch (e) {}
    });
}

// `done(source, error)`.
function readSource(url, done) {
    if (isInline(url)) {
        const m = inlineSources();
        done(m.hasOwnProperty(url) ? m[url] : "", m.hasOwnProperty(url) ? "" : "The script's source is missing");
        return;
    }
    fileRequest("GET", url, null, function (text, error) {
        if (error !== "") done("", "Could not read the file: " + error);
        else if (text === "") done("", "Could not read the file: it is missing or empty");
        else done(text, "");
    });
}

// `done(error)`.
function writeSource(url, source, done) {
    if (isInline(url)) {
        saveInlineSource(url, source);
        done("");
        return;
    }
    fileRequest("PUT", url, source, function (text, error) {
        done(error === "" ? "" : "Could not write the file: " + error);
    });
}

// `done(error)` runs once the script is registered or has failed.
function readScript(url, done) {
    readSource(url, function (source, readError) {
        const err = registerSource(url, source, readError);
        if (done) done(err);
    });
}

function addScript(url, done) {
    readScript(url, function (err) {
        saveScriptUrls();
        if (done) done(err);
    });
}

// A new inline script from the template, with an id and name nothing uses.
// Returns its URL.
function newInlineScript() {
    const inline = inlineSources();
    let n = 1;
    while (Handlers.get("script-" + n) !== null || inline.hasOwnProperty(INLINE + "script-" + n)
           || scriptRecord(INLINE + "script-" + n) !== null)
        n++;
    const url = INLINE + "script-" + n;
    const source = Template.make("script-" + n, "Script " + n);
    saveInlineSource(url, source);
    registerSource(url, source, "");
    saveScriptUrls();
    return url;
}

// Saves the source where the script lives, then compiles it. The source is
// kept even when it does not compile, so no edit is lost; the handler that was
// running keeps running. `done({ error, line, saved })`.
function applyScript(url, source, done) {
    writeSource(url, source, function (writeError) {
        if (writeError !== "") {
            if (done) done({ error: writeError, line: -1, saved: false, running: false });
            return;
        }
        const err = registerSource(url, source, "");
        if (scriptRecord(url) !== null && savedScriptUrls().indexOf(url) < 0)
            saveScriptUrls();
        const rec = scriptRecord(url);
        if (done) done({ error: err, line: rec ? rec.line : -1, saved: true,
                         // A failed apply leaves the previous version registered.
                         running: !!rec && rec.id !== "" && Handlers.get(rec.id) !== null });
    });
}

// What the scripts view calls a script: its handler's name once it has one.
function scriptName(url) {
    const rec = scriptRecord(url);
    const h = (rec && rec.id !== "") ? Handlers.get(rec.id) : null;
    return h ? h.name : fileName(url);
}

function reloadScripts() {
    for (let s of Handlers.scripts().slice())
        readScript(s.url);
}

function reloadScript(url) {
    readScript(url);
}

function removeScript(url) {
    const id = Handlers.removeScript(url);
    if (id !== "") handlersChanged(id);
    if (isInline(url)) saveInlineSource(url, null);
    saveScriptUrls();
    updateHandlerList();
    updateInputList();
    updateOutputList();
}

function updateHandlerList() {
    if (typeof handlerListModel === "undefined") return;
    const rows = [];
    for (let h of Handlers.all()) {
        if (!h.builtin) continue;
        rows.push({ handlerId: h.id, name: h.name, url: "", builtin: true, inline: false,
                    directions: directionsOf(h), error: "" });
    }
    for (let s of Handlers.scripts()) {
        const h = s.id !== "" ? Handlers.get(s.id) : null;
        rows.push({ handlerId: s.id, name: h ? h.name : fileName(s.url), url: s.url,
                    builtin: false, inline: isInline(s.url),
                    directions: h ? directionsOf(h) : "", error: s.error });
    }
    syncModel(handlerListModel, rows, ["url", "handlerId"]);
}

function directionsOf(h) {
    if (h.hasInput && h.hasOutput) return "in / out";
    return h.hasInput ? "in" : "out";
}

function fileName(url) {
    if (isInline(url)) return url.substring(INLINE.length);
    const i = url.lastIndexOf("/");
    return i < 0 ? url : decodeURIComponent(url.substring(i + 1));
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
                     scaleZ: scaleOf(i, "scaleZ"),
                     params: i.params || {} };
        }),
        outputs: outputs.map(function (o) {
            return { id: o.id, name: o.name, protocol: o.protocol,
                     host: o.host, port: o.port,
                     params: o.params || {} };
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
    const raw = appSettings.savedConfiguration || "";
    let cfg = null;
    try {
        if (raw !== "")
            cfg = JSON.parse(raw);
    } catch (e) {
        console.log("Could not parse saved configuration:", e);
    }

    if (cfg && cfg.version === 2 && cfg.inputs && cfg.inputs.length > 0) {
        restoreV2(cfg);
    } else if (raw !== "") {
        // Stored but unusable. migrateFromV1() ends in saveConfiguration(), which
        // would overwrite it, so leave the stored bytes alone.
        console.log("Saved configuration unusable; keeping the stored copy.");
        createInput("Input 1", appSettings.listenPort, "Auto");
    } else {
        migrateFromV1();
    }

    reindexRoutes();
    updateInputList();
    updateOutputList();
}

// Devices are addressed by id. An undefined id also makes g_nextId NaN, which
// never compares equal to itself.
function usableDevices(list) {
    const seen = {};
    const out = [];
    for (let e of list || []) {
        if (!e || typeof e !== "object") continue;
        if (typeof e.id !== "number" || !isFinite(e.id)) {
            console.log("Skipping a saved device with no usable id");
            continue;
        }
        if (seen[e.id]) {
            console.log("Skipping a saved device with a duplicate id:", e.id);
            continue;
        }
        seen[e.id] = true;
        out.push(e);
    }
    return out;
}

function savedParams(p) {
    return (p && typeof p === "object" && !Array.isArray(p)) ? p : {};
}

function restoreV2(cfg) {
    const savedInputs = usableDevices(cfg.inputs);
    const savedOutputs = usableDevices(cfg.outputs);

    let maxId = 0;
    for (let si of savedInputs) maxId = Math.max(maxId, si.id);
    for (let so of savedOutputs) maxId = Math.max(maxId, so.id);
    g_nextId = maxId + 1;

    for (let si of savedInputs) {
        const inp = {
            id: si.id, name: si.name, protocol: si.protocol || "Auto",
            port: si.port, enabled: si.enabled !== false,
            scaleX: (si.scaleX === undefined) ? 1 : si.scaleX,
            scaleY: (si.scaleY === undefined) ? 1 : si.scaleY,
            scaleZ: (si.scaleZ === undefined) ? 1 : si.scaleZ,
            params: savedParams(si.params),
            listening: false, error: "",
            udp: null, osc: null, rt: null
        };
        inputs.push(inp);
        if (inp.enabled)
            openInput(inp);
    }

    // A protocol whose script is missing keeps its id and params, so the
    // device comes back whole once the script does.
    for (let so of savedOutputs) {
        const dev = {
            id: so.id, name: so.name, host: so.host,
            port: so.port, protocol: so.protocol,
            params: savedParams(so.params),
            udp: null, rt: null
        };
        openOutputSocket(dev);
        outputs.push(dev);
    }

    for (let sr of cfg.routes || []) {
        if (!sr || !findInput(sr.inputId) || !findOutput(sr.outputId)) {
            console.log("Skipping a saved route with no device at one end");
            continue;
        }
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

// v1 was one implicit input and a flat output list, each output carrying its
// own offset and `active` flag. The v1 keys are left in place so a rollback
// keeps its setup.
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
