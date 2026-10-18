.pragma library
.import "handlers/Spm.js" as Spm
.import "handlers/SpatGRIS.js" as SpatGRISHandler
.import "handlers/AdmOsc.js" as AdmOscHandler
.import "handlers/SpatRevolution.js" as SpatRevolutionHandler

// Protocol handler registry.
//
// A handler is a descriptor (see docs/HANDLERS.md):
//
//   { apiVersion: 1, id, name, defaultPort?, params?, matches?,
//     createInput?(ctx), createOutput?(ctx), native?: { prefix, source(address) } }
//
// The bundled ones are registered at load; user scripts are compiled from
// source and registered on top. A `.pragma library`, so the engine, the
// window and the tests share one registry.

var PARAM_TYPES = { "int": true, "real": true, "bool": true, "string": true, "enum": true };

// Registration order is the order "Auto" tries decoders in, and the order the
// protocol menus list them in: bundled first.
var g_list = [];
var g_byId = {};

// [{ id, url, error }] for every user script, loaded or not.
var g_scripts = [];

function get(id) {
    return g_byId.hasOwnProperty(id) ? g_byId[id] : null;
}

function all() {
    return g_list;
}

function isBuiltin(id) {
    const d = get(id);
    return d !== null && d.builtin === true;
}

// "" when usable, otherwise why not.
function validate(d) {
    if (!d || typeof d !== "object" || Object.keys(d).length === 0)
        return "the script does not export a handler object (module.exports = { … })";
    if (d.apiVersion !== Spm.API_VERSION)
        return "unsupported apiVersion " + d.apiVersion + " (expected " + Spm.API_VERSION + ")";
    if (typeof d.id !== "string" || d.id.length === 0) return "missing id";
    if (d.id === "Auto") return "\"Auto\" is reserved";
    if (d.name !== undefined && typeof d.name !== "string") return "name must be a string";
    const hasIn = typeof d.createInput === "function";
    const hasOut = typeof d.createOutput === "function";
    if (!hasIn && !hasOut) return "defines neither createInput nor createOutput";
    if (d.createInput !== undefined && !hasIn) return "createInput must be a function";
    if (d.createOutput !== undefined && !hasOut) return "createOutput must be a function";
    if (d.matches !== undefined && (typeof d.matches !== "string" || d.matches[0] !== "/"))
        return "matches must be an address prefix starting with /";
    if (d.defaultPort !== undefined
            && (typeof d.defaultPort !== "number" || d.defaultPort < 1 || d.defaultPort > 65535))
        return "defaultPort must be between 1 and 65535";
    if (d.native !== undefined) {
        if (!d.native || typeof d.native.prefix !== "string" || d.native.prefix[0] !== "/")
            return "native.prefix must be an address prefix starting with /";
        if (d.native.source !== undefined && typeof d.native.source !== "function")
            return "native.source must be a function";
    }
    if (d.params !== undefined) {
        if (!Array.isArray(d.params)) return "params must be an array";
        const seen = {};
        for (let p of d.params) {
            if (!p || typeof p.key !== "string" || p.key.length === 0) return "a param has no key";
            if (seen[p.key]) return "duplicate param " + p.key;
            seen[p.key] = true;
            if (!PARAM_TYPES[p.type]) return "param " + p.key + " has unknown type " + p.type;
            if (p.type === "enum" && (!Array.isArray(p.options) || p.options.length === 0))
                return "enum param " + p.key + " needs options";
        }
    }
    return "";
}

// Adds or replaces. Bundled handlers cannot be replaced by a script.
function register(d, url) {
    const err = validate(d);
    if (err !== "") return err;

    const existing = get(d.id);
    if (existing !== null && existing.builtin)
        return "id \"" + d.id + "\" is a built-in protocol";
    if (existing !== null && existing.url !== url)
        return "id \"" + d.id + "\" is already used by " + existing.url;

    const entry = {
        id: d.id,
        name: d.name || d.id,
        builtin: url === null,
        url: url,
        descriptor: d,
        defaultPort: d.defaultPort || 8000,
        params: d.params || [],
        hasInput: typeof d.createInput === "function",
        hasOutput: typeof d.createOutput === "function",
        matches: d.matches || null,
        native: d.native || null
    };

    if (existing !== null) {
        g_list[g_list.indexOf(existing)] = entry;
    } else {
        g_list.push(entry);
    }
    g_byId[d.id] = entry;
    return "";
}

function unregister(id) {
    const e = get(id);
    if (e === null || e.builtin) return false;
    g_list.splice(g_list.indexOf(e), 1);
    delete g_byId[id];
    return true;
}

// ----- User scripts ------------------------------------------------------ //
// A script is a CommonJS-style body: it assigns `module.exports`. It runs with
// `spm` in scope and with `Qt`, `XMLHttpRequest` and `Protocols` shadowed.
// That keeps handlers from reaching into the app by accident -- and keeps them
// movable to another thread later -- but it is not a security boundary.
//
// Compiled with an indirect eval rather than `new Function`: V4 then reports
// syntax and runtime errors at the script's own line numbers ("eval code:N"),
// which the editor points at. The wrapper's header shares line 1 with the
// script, so the numbers need no adjustment.
var g_eval = eval;

function compile(source) {
    const module = { exports: {} };
    let factory;
    try {
        factory = g_eval("(function (module, exports, spm, Qt, XMLHttpRequest, Protocols) {\"use strict\";"
                         + source + "\n})");
    } catch (e) {
        return { descriptor: null, error: describeError(e), line: scriptLine(e) };
    }
    try {
        factory(module, module.exports, Spm.api, undefined, undefined, undefined);
    } catch (e) {
        return { descriptor: null, error: describeError(e), line: scriptLine(e) };
    }
    return { descriptor: module.exports, error: "", line: -1 };
}

// The line in a user script an error comes from, or -1.
function scriptLine(e) {
    if (!e) return -1;
    const m = /eval code:(\d+)/.exec(String(e.stack || ""));
    if (m) return parseInt(m[1]);
    return -1;
}

function describeError(e) {
    const line = scriptLine(e);
    return String(e) + (line > 0 ? " (line " + line + ")" : "");
}

function scriptFor(url) {
    for (let s of g_scripts)
        if (s.url === url) return s;
    return null;
}

// Compiles and registers the source of the script at `url`, replacing what it
// registered before. Returns the error, or "".
//
// On failure the version registered before, if any, stays registered: an edit
// that does not compile leaves the running handler alone.
function loadScript(url, source) {
    let s = scriptFor(url);
    if (s === null) {
        s = { id: "", url: url, error: "", line: -1 };
        g_scripts.push(s);
    }

    const c = compile(source);
    let err = c.error;
    if (err === "") err = validate(c.descriptor);
    if (err === "" && s.id !== "" && s.id !== c.descriptor.id)
        unregister(s.id);
    if (err === "") err = register(c.descriptor, url);

    s.error = err;
    s.line = c.line;
    if (err === "")
        s.id = c.descriptor.id;
    return err;
}

function scriptFailed(url, error) {
    let s = scriptFor(url);
    if (s === null) {
        s = { id: "", url: url, error: "", line: -1 };
        g_scripts.push(s);
    }
    s.error = error;
    s.line = -1;
}

function removeScript(url) {
    const s = scriptFor(url);
    if (s === null) return "";
    g_scripts.splice(g_scripts.indexOf(s), 1);
    if (s.id !== "" && get(s.id) !== null && get(s.id).url === url) {
        unregister(s.id);
        return s.id;
    }
    return "";
}

function scripts() {
    return g_scripts;
}

// ----- Params ------------------------------------------------------------ //

function coerceParam(p, v) {
    switch (p.type) {
    case "int": {
        let n = parseInt(v);
        if (isNaN(n)) return undefined;
        if (typeof p.min === "number") n = Math.max(p.min, n);
        if (typeof p.max === "number") n = Math.min(p.max, n);
        return n;
    }
    case "real": {
        let n = parseFloat(v);
        if (isNaN(n)) return undefined;
        if (typeof p.min === "number") n = Math.max(p.min, n);
        if (typeof p.max === "number") n = Math.min(p.max, n);
        return n;
    }
    case "bool":
        return v === true || v === "true" || v === 1;
    case "string":
        return (v === null || v === undefined) ? undefined : String(v);
    case "enum":
        return p.options.indexOf(v) >= 0 ? v : undefined;
    }
    return undefined;
}

function defaultOf(p) {
    if (p.default !== undefined) {
        const v = coerceParam(p, p.default);
        if (v !== undefined) return v;
    }
    switch (p.type) {
    case "int": case "real": return typeof p.min === "number" ? p.min : 0;
    case "bool": return false;
    case "string": return "";
    case "enum": return p.options[0];
    }
    return null;
}

// The values a device runs with: the saved ones that are still valid, and
// defaults for the rest. Keys the handler no longer declares are kept, so a
// script that briefly drops a param does not erase the setting.
function resolveParams(entry, saved) {
    const out = {};
    if (saved && typeof saved === "object")
        for (let k in saved) out[k] = saved[k];
    if (entry === null) return out;
    for (let p of entry.params) {
        const v = (saved && saved.hasOwnProperty(p.key)) ? coerceParam(p, saved[p.key]) : undefined;
        out[p.key] = (v === undefined) ? defaultOf(p) : v;
    }
    return out;
}

// ----- Input tables ------------------------------------------------------ //
// What createInput returns: functions keyed by address pattern, plus an
// optional "*" for anything else under the handler's `matches` prefix.
function compileInputTable(table) {
    const patterns = [];
    let fallback = null;
    for (let key in table) {
        const fn = table[key];
        if (typeof fn !== "function") continue;
        if (key === "*") fallback = fn;
        else if (key[0] === "/") patterns.push({ p: Spm.compilePattern(key), fn: fn });
    }
    return { patterns: patterns, fallback: fallback };
}

// ----- Bundled ----------------------------------------------------------- //

function registerBuiltins() {
    for (let d of [SpatGRISHandler.module.exports,
                   AdmOscHandler.module.exports,
                   SpatRevolutionHandler.module.exports]) {
        const err = register(d, null);
        if (err !== "") console.log("Bundled handler", d && d.id, "rejected:", err);
    }
}

registerBuiltins();
