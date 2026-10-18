// SPDX-License-Identifier: GPL-3.0-or-later
// © Société des arts technologiques
//
// Protocol handlers: the registry, user scripts, and the engine's message path
// around them (address resolution, verbatim passthrough, params, failures).
import QtCore
import QtQuick
import QtTest
import "../qml/spm/Engine.js" as Engine
import "../qml/spm/Handlers.js" as Handlers
import "../qml/spm/handlers/Spm.js" as Spm
import "../qml/spm/handlers/Template.js" as Template

TestCase {
    id: tc
    name: "handlers"

    // ---- the world Engine.js expects ---------------------------------- //
    property var inputs: []
    property var outputs: []
    property var routes: []
    property bool monitorActive: false

    property QtObject appSettings: QtObject {
        property bool logReceivedMessages: false
        property bool logSentMessages: false
        property int monitorMaxRate: 500
        property int listenPort: 18032
        property string savedConfiguration: ""
        property string savedOutputDevices: "[]"
        property string handlerScripts: "[]"
        property string inlineScripts: "{}"
    }

    function initTestCase() {
        var g = (function () { return this; })();   // Qt 6.4 has no globalThis
        g.Protocols = {
            osc: function () { return { processMessage: function () {} }; },
            inboundUDP: function (cfg) { return { close: function () {} }; },
            outboundUDP: function () { return { osc: function () {}, close: function () {} }; }
        };
    }

    function syncCurrentInput() {}
    ListModel { id: inputListModel }
    ListModel { id: outputListModel }
    ListModel { id: routeListModel }
    ListModel { id: matrixModel }

    // Scripts registered by a test, removed again afterwards: the registry is
    // a library, shared with every other test file.
    property var loadedUrls: []

    function cleanup() {
        for (let u of loadedUrls) {
            const id = Handlers.removeScript(u);
            if (id !== "") Engine.handlersChanged(id);
        }
        loadedUrls = [];
        for (let s of Handlers.scripts().slice())
            if (s.url.startsWith("inline:")) Engine.removeScript(s.url);
        appSettings.handlerScripts = "[]";
        appSettings.inlineScripts = "{}";
        tc.inputs = [];
        tc.outputs = [];
        tc.routes = [];
        Engine.reindexRoutes();
    }

    function load(url, source) {
        loadedUrls.push(url);
        const err = Handlers.loadScript(url, source);
        Engine.handlersChanged(Handlers.scripts().filter(function (s) { return s.url === url; })[0].id);
        return err;
    }

    // Records what it was sent. Encoders reuse their buffers, so a sink that
    // keeps values must copy them -- score's udp.osc() does, by serializing.
    function sink(id, protocol, params) {
        const out = { id: id, name: "out" + id, protocol: protocol, host: "h", port: 1,
                      params: params || {}, sent: [], udp: null, rt: null };
        out.udp = { osc: function (a, v) { out.sent.push({ address: a, value: v.slice() }); } };
        return out;
    }

    function input(id, protocol, params) {
        return { id: id, name: "in" + id, protocol: protocol, port: 1, enabled: true,
                 listening: true, error: "", params: params || {}, udp: null, osc: null, rt: null };
    }

    function route(inputId, outputId, offset, min, max) {
        return { inputId: inputId, outputId: outputId, enabled: true,
                 sourceOffset: offset || 0,
                 srcMin: min === undefined ? null : min,
                 srcMax: max === undefined ? null : max };
    }

    function world(ins, outs, rts) {
        tc.inputs = ins;
        tc.outputs = outs;
        tc.routes = rts;
        Engine.reindexRoutes();
    }

    function addresses(out) {
        return out.sent.map(function (m) { return m.address; });
    }

    // ---------------------------------------------------------------- //
    // Registry                                                          //
    // ---------------------------------------------------------------- //

    function test_builtins_are_registered_in_auto_order() {
        const ids = Handlers.all().filter(function (h) { return h.builtin; })
                                  .map(function (h) { return h.id; });
        compare(ids, ["SpatGRIS", "ADM-OSC", "SPAT Revolution"]);
        for (let id of ids) {
            verify(Handlers.get(id).hasInput, id + " decodes");
            verify(Handlers.get(id).hasOutput, id + " encodes");
        }
    }

    function test_invalid_descriptors_are_rejected_data() {
        const ok = "createOutput: function () { return {}; }";
        return [
            { tag: "no export",      src: "", error: "does not export" },
            { tag: "wrong api",      src: "module.exports = { apiVersion: 2, id: 'x', " + ok + " };", error: "apiVersion" },
            { tag: "no id",          src: "module.exports = { apiVersion: 1, " + ok + " };", error: "missing id" },
            { tag: "reserved id",    src: "module.exports = { apiVersion: 1, id: 'Auto', " + ok + " };", error: "reserved" },
            { tag: "no sides",       src: "module.exports = { apiVersion: 1, id: 'x' };", error: "neither" },
            { tag: "bad matches",    src: "module.exports = { apiVersion: 1, id: 'x', matches: 'adm', " + ok + " };", error: "matches" },
            { tag: "bad port",       src: "module.exports = { apiVersion: 1, id: 'x', defaultPort: 70000, " + ok + " };", error: "defaultPort" },
            { tag: "bad param type", src: "module.exports = { apiVersion: 1, id: 'x', params: [{ key: 'a', type: 'float' }], " + ok + " };", error: "unknown type" },
            { tag: "enum, no options", src: "module.exports = { apiVersion: 1, id: 'x', params: [{ key: 'a', type: 'enum' }], " + ok + " };", error: "options" },
            { tag: "dup param",      src: "module.exports = { apiVersion: 1, id: 'x', params: [{ key: 'a', type: 'int' }, { key: 'a', type: 'int' }], " + ok + " };", error: "duplicate" },
            { tag: "syntax error",   src: "module.exports = {", error: "SyntaxError" },
            { tag: "throws",         src: "throw new Error('boom');", error: "boom" },
            { tag: "builtin id",     src: "module.exports = { apiVersion: 1, id: 'ADM-OSC', " + ok + " };", error: "built-in" }
        ];
    }
    function test_invalid_descriptors_are_rejected(row) {
        const url = "test://invalid/" + row.tag;
        loadedUrls.push(url);
        const err = Handlers.loadScript(url, row.src);
        verify(err.indexOf(row.error) >= 0, "got: " + err);
        const s = Handlers.scripts().filter(function (x) { return x.url === url; })[0];
        compare(s.error, err, "the failure is kept for the scripts view");
        compare(Handlers.get("x"), null);
        verify(Handlers.get("ADM-OSC").builtin, "the bundled handler is untouched");
    }

    // Scripts cannot reach the app by accident, and do not leak globals.
    function test_scripts_run_strict_with_app_globals_shadowed() {
        const err = load("test://shadow", `
            module.exports = {
                apiVersion: 1, id: "shadow-probe",
                seen: [typeof Qt, typeof XMLHttpRequest, typeof Protocols, typeof spm],
                createOutput: function () { return {}; }
            };
            try { leakedGlobal = 1; } catch (e) { module.exports.strict = true; }
        `);
        compare(err, "");
        const d = Handlers.get("shadow-probe").descriptor;
        compare(d.seen, ["undefined", "undefined", "undefined", "object"]);
        verify(d.strict, "assigning an undeclared name throws");
    }

    function test_spm_is_frozen() {
        verify(Object.isFrozen(Spm.api));
    }

    function test_reloading_a_script_replaces_its_handler() {
        const v1 = "module.exports = { apiVersion: 1, id: 'reloadable', name: 'One', createOutput: function () { return {}; } };";
        const v2 = "module.exports = { apiVersion: 1, id: 'reloadable', name: 'Two', createOutput: function () { return {}; } };";
        compare(load("test://reload", v1), "");
        compare(Handlers.get("reloadable").name, "One");
        compare(Handlers.loadScript("test://reload", v2), "");
        compare(Handlers.get("reloadable").name, "Two");
        compare(Handlers.all().filter(function (h) { return h.id === "reloadable"; }).length, 1);
    }

    function test_a_script_that_changes_id_releases_the_old_one() {
        load("test://rename", "module.exports = { apiVersion: 1, id: 'old-id', createOutput: function () { return {}; } };");
        Handlers.loadScript("test://rename", "module.exports = { apiVersion: 1, id: 'new-id', createOutput: function () { return {}; } };");
        compare(Handlers.get("old-id"), null);
        verify(Handlers.get("new-id") !== null);
    }

    function test_two_scripts_cannot_share_an_id() {
        load("test://first", "module.exports = { apiVersion: 1, id: 'shared', createOutput: function () { return {}; } };");
        loadedUrls.push("test://second");
        const err = Handlers.loadScript("test://second",
                                        "module.exports = { apiVersion: 1, id: 'shared', createOutput: function () { return {}; } };");
        verify(err.indexOf("already used") >= 0, err);
        compare(Handlers.get("shared").url, "test://first");
    }

    // ---------------------------------------------------------------- //
    // Address patterns and templates                                    //
    // ---------------------------------------------------------------- //

    function test_pattern_matching_data() {
        return [
            { tag: "index",          pattern: "/adm/obj/{n}/xyz", address: "/adm/obj/12/xyz", n: 12 },
            { tag: "leading zeros",  pattern: "/adm/obj/{n}/xyz", address: "/adm/obj/007/xyz", n: 7 },
            { tag: "no index",       pattern: "/adm/obj/{n}/xyz", address: "/adm/obj//xyz", n: -2 },
            { tag: "not digits",     pattern: "/adm/obj/{n}/xyz", address: "/adm/obj/a/xyz", n: -2 },
            { tag: "deeper",         pattern: "/adm/obj/{n}/x",   address: "/adm/obj/1/y/x", n: -2 },
            { tag: "suffix only",    pattern: "/adm/obj/{n}/x",   address: "/adm/obj/1/xyz", n: -2 },
            { tag: "wildcard",       pattern: "/adm/obj/{n}/x",   address: "/adm/obj/*/x", n: -2 },
            { tag: "literal",        pattern: "/spat/serv",       address: "/spat/serv", n: -1 },
            { tag: "literal miss",   pattern: "/spat/serv",       address: "/spat/servx", n: -2 },
            { tag: "trailing index", pattern: "/track/{n}",       address: "/track/3", n: 3 }
        ];
    }
    function test_pattern_matching(row) {
        compare(Spm.matchPattern(Spm.compilePattern(row.pattern), row.address), row.n);
    }

    function test_address_templates() {
        const t = Spm.addressTemplate("/source/{n}/aed");
        compare(t(3), "/source/3/aed");
        compare(t(3), "/source/3/aed", "cached");
        compare(t(-1), "/source/-1/aed", "out of the cache range still formats");
        compare(Spm.addressTemplate("/fixed")(9), "/fixed");
    }

    // ---------------------------------------------------------------- //
    // User handlers on the message path                                 //
    // ---------------------------------------------------------------- //

    // A scripted input feeding every bundled output, and a bundled input
    // feeding a scripted output.
    readonly property string probeSource: `
        module.exports = {
            apiVersion: 1, id: "probe", name: "Probe", defaultPort: 9999,
            matches: "/probe/",
            params: [{ key: "gain", type: "real", default: 2 }],
            createInput: function (ctx) {
                return {
                    "/probe/{n}/aed": function (n, a, ev) {
                        ev.type = spm.POSITION; ev.source = n; ev.coords = spm.SPHERICAL;
                        ev.azimuth = a[0]; ev.elevation = a[1]; ev.distance = a[2];
                        return true;
                    }
                };
            },
            createOutput: function (ctx) {
                const b = [0, 0, 0];
                const cart = { x: 0, y: 0, z: 0 };
                return {
                    position: function (ev) {
                        spm.toCartesian(ev, cart);
                        b[0] = cart.x * ctx.params.gain; b[1] = cart.y * ctx.params.gain; b[2] = cart.z * ctx.params.gain;
                        ctx.send("/probe/" + ev.source + "/xyz", b);
                    }
                };
            }
        };`

    function test_a_scripted_input_feeds_bundled_outputs() {
        compare(load("test://probe", probeSource), "");
        const inp = input(1, "probe");
        const sg = sink(10, "SpatGRIS"), adm = sink(11, "ADM-OSC");
        world([inp], [sg, adm], [route(1, 10), route(1, 11, 4)]);

        Engine.onInputValueReceived(inp, "/probe/2/aed", [30, 10, 1]);

        compare(sg.sent.length, 1);
        compare(sg.sent[0].value, ["deg", 2, 30, 10, 1, 0, 0]);
        compare(addresses(adm), ["/adm/obj/6/aed", "/adm/obj/6/w"], "the route offset applies");
        fuzzyCompare(adm.sent[0].value[0], -30, 1e-9, "ADM azimuth flips");
    }

    function test_a_bundled_input_feeds_a_scripted_output() {
        load("test://probe", probeSource);
        const inp = input(1, "ADM-OSC");
        const out = sink(10, "probe");
        world([inp], [out], [route(1, 10)]);

        Engine.onInputValueReceived(inp, "/adm/obj/3/xyz", [0.1, 0.2, 0.3]);

        compare(addresses(out), ["/probe/3/xyz"]);
        fuzzyCompare(out.sent[0].value[0], 0.2, 1e-9, "the default gain of 2");
        fuzzyCompare(out.sent[0].value[2], 0.6, 1e-9);
    }

    // A handler that declares `matches` joins Auto, after the bundled ones.
    function test_auto_inputs_try_scripted_decoders_too() {
        load("test://probe", probeSource);
        const inp = input(1, "Auto");
        const out = sink(10, "SpatGRIS");
        world([inp], [out], [route(1, 10)]);

        Engine.onInputValueReceived(inp, "/probe/5/aed", [0, 0, 1]);
        Engine.onInputValueReceived(inp, "/adm/obj/6/xyz", [0, 0, 0]);
        compare(out.sent.map(function (m) { return m.value[1]; }), [5, 6]);
    }

    function test_a_handler_without_matches_stays_out_of_auto() {
        load("test://nomatch", `module.exports = { apiVersion: 1, id: "nomatch",
            createInput: function () { return { "*": function (n, a, ev) {
                ev.type = spm.CLEAR; ev.source = 1; return true; } }; } };`);
        const inp = input(1, "Auto");
        const out = sink(10, "SpatGRIS");
        world([inp], [out], [route(1, 10)]);
        Engine.onInputValueReceived(inp, "/anything", [1]);
        compare(out.sent.length, 0);

        // Declared, it takes every address.
        const own = input(2, "nomatch");
        world([own], [out], [route(2, 10)]);
        Engine.onInputValueReceived(own, "/anything", [1]);
        compare(out.sent[0].value, ["clr", 1]);
    }

    // emit() routes more than one event from a single message.
    function test_a_decoder_can_emit_several_events() {
        load("test://multi", `module.exports = { apiVersion: 1, id: "multi",
            createInput: function (ctx) { return { "/both/{n}": function (n, a, ev) {
                ev.type = spm.CLEAR; ev.source = n; ctx.emit();
                ev.source = n + 1; ctx.emit();
                return false; } }; } };`);
        const inp = input(1, "multi");
        const out = sink(10, "SpatGRIS");
        world([inp], [out], [route(1, 10)]);
        Engine.onInputValueReceived(inp, "/both/3", []);
        compare(out.sent.map(function (m) { return m.value[1]; }), [3, 4]);
    }

    // ---------------------------------------------------------------- //
    // Verbatim passthrough                                              //
    // ---------------------------------------------------------------- //

    // ADM features with no place in the event model reach ADM outputs from
    // any input, with the route offset applied where there is an index.
    function test_unmodelled_adm_is_forwarded_verbatim_data() {
        return [
            { tag: "gain",     address: "/adm/obj/3/gain", expected: "/adm/obj/19/gain" },
            { tag: "short",    address: "/adm/obj/3/aed",  expected: "/adm/obj/19/aed" },
            { tag: "listener", address: "/adm/lis/azim",   expected: "/adm/lis/azim" },
            { tag: "wildcard", address: "/adm/obj/*/azim", expected: "/adm/obj/*/azim" }
        ];
    }
    function test_unmodelled_adm_is_forwarded_verbatim(row) {
        const inp = input(1, "SpatGRIS");
        const adm = sink(10, "ADM-OSC"), sg = sink(11, "SpatGRIS");
        world([inp], [adm, sg], [route(1, 10, 16), route(1, 11)]);

        Engine.onInputValueReceived(inp, row.address, [0.5]);

        compare(addresses(adm), [row.expected]);
        compare(adm.sent[0].value, [0.5]);
        compare(sg.sent.length, 0, "other protocols do not take it");
    }

    function test_verbatim_forwarding_respects_the_range_filter() {
        const inp = input(1, "ADM-OSC");
        const adm = sink(10, "ADM-OSC");
        world([inp], [adm], [route(1, 10, 0, 1, 4)]);
        Engine.onInputValueReceived(inp, "/adm/obj/9/gain", [1]);
        Engine.onInputValueReceived(inp, "/adm/obj/2/gain", [1]);
        Engine.onInputValueReceived(inp, "/adm/env/size", [1]);
        compare(addresses(adm), ["/adm/obj/2/gain", "/adm/env/size"]);
    }

    // ---------------------------------------------------------------- //
    // Address cache                                                     //
    // ---------------------------------------------------------------- //

    function test_the_address_cache_is_bounded() {
        const inp = input(1, "ADM-OSC");
        world([inp], [sink(10, "ADM-OSC")], [route(1, 10)]);
        for (let i = 0; i < Engine.ADDRESS_CACHE_MAX + 50; i++)
            Engine.onInputValueReceived(inp, "/adm/obj/" + i + "/x", [0.1]);
        verify(inp.rt.cache.size <= Engine.ADDRESS_CACHE_MAX);
        verify(inp.rt.cache.size > 0);
    }

    // A protocol change rebuilds the decoder: no accumulated state survives.
    function test_a_protocol_change_resets_the_accumulators() {
        const inp = input(1, "ADM-OSC");
        const out = sink(10, "SpatGRIS");
        world([inp], [out], [route(1, 10)]);
        tc.inputs = [inp];
        Engine.onInputValueReceived(inp, "/adm/obj/1/xyz", [0.5, 0.5, 0.5]);

        Engine.updateInput(1, { protocol: "Auto" });
        Engine.onInputValueReceived(inp, "/adm/obj/1/x", [0.9]);
        compare(out.sent[1].value, ["car", 1, 0.9, 0, 0, 0, 0], "y and z back at defaults");
    }

    // ---------------------------------------------------------------- //
    // Failures                                                          //
    // ---------------------------------------------------------------- //

    function test_a_throwing_encoder_does_not_stop_the_others() {
        load("test://broken", `module.exports = { apiVersion: 1, id: "broken",
            createOutput: function () { return { position: function () { throw new Error("nope"); } }; } };`);
        const inp = input(1, "ADM-OSC");
        const bad = sink(10, "broken"), good = sink(11, "SpatGRIS");
        world([inp], [bad, good], [route(1, 10), route(1, 11)]);

        Engine.onInputValueReceived(inp, "/adm/obj/1/xyz", [0, 0, 0]);
        Engine.onInputValueReceived(inp, "/adm/obj/1/xyz", [0, 0, 0]);

        compare(good.sent.length, 2, "the other output kept receiving");
        verify(bad.handlerError.indexOf("nope") >= 0);
        compare(bad.handlerErrors, 2);
        verify(Engine.handlerStatus(bad, "output").indexOf("nope") >= 0, "and the row shows it");
    }

    function test_a_throwing_decoder_drops_only_that_message() {
        load("test://brokenin", `module.exports = { apiVersion: 1, id: "brokenin",
            createInput: function () { return { "/x/{n}": function (n) {
                if (n === 1) throw new Error("bad"); return false; } }; } };`);
        const inp = input(1, "brokenin");
        world([inp], [sink(10, "SpatGRIS")], [route(1, 10)]);
        Engine.onInputValueReceived(inp, "/x/1", []);
        Engine.onInputValueReceived(inp, "/x/2", []);
        compare(inp.handlerErrors, 1);
    }

    function test_a_factory_that_throws_leaves_the_device_inert() {
        load("test://badfactory", `module.exports = { apiVersion: 1, id: "badfactory",
            createOutput: function () { throw new Error("no instance"); } };`);
        const inp = input(1, "ADM-OSC");
        const out = sink(10, "badfactory");
        world([inp], [out], [route(1, 10)]);
        Engine.onInputValueReceived(inp, "/adm/obj/1/xyz", [0, 0, 0]);
        compare(out.sent.length, 0);
        verify(out.handlerError.indexOf("no instance") >= 0);
    }

    // ---------------------------------------------------------------- //
    // Missing handlers and persistence                                  //
    // ---------------------------------------------------------------- //

    // A device on a protocol whose script is absent keeps its protocol and
    // params through a save, and works once the script arrives.
    function test_a_missing_handler_keeps_the_device() {
        appSettings.savedConfiguration = JSON.stringify({
            version: 2,
            inputs: [{ id: 1, name: "in", protocol: "ADM-OSC", port: 18032, enabled: false }],
            outputs: [{ id: 2, name: "later", protocol: "probe", host: "h", port: 1,
                        params: { gain: 10 } }],
            routes: [{ inputId: 1, outputId: 2, enabled: true, sourceOffset: 0 }]
        });
        Engine.restoreConfiguration();
        compare(tc.outputs.length, 1);
        compare(tc.routes.length, 1, "the route survives too");
        compare(Engine.handlerStatus(tc.outputs[0], "output"), "Handler not loaded: probe");
        verify(Engine.protocolOptions("output").ids.indexOf("probe") >= 0, "the picker can show it");

        Engine.saveConfiguration();
        const saved = JSON.parse(appSettings.savedConfiguration);
        compare(saved.outputs[0].protocol, "probe");
        compare(saved.outputs[0].params.gain, 10);

        // The script arrives.
        const out = tc.outputs[0];
        const sent = [];
        out.udp = { osc: function (a, v) { sent.push(v.slice()); } };
        load("test://probe", probeSource);
        compare(Engine.handlerStatus(out, "output"), "");
        Engine.onInputValueReceived(tc.inputs[0], "/adm/obj/1/xyz", [0.1, 0, 0]);
        fuzzyCompare(sent[0][0], 1.0, 1e-9, "with its saved gain");
    }

    function test_params_round_trip_through_the_configuration() {
        load("test://probe", probeSource);
        // A configuration with no input is treated as unusable.
        tc.inputs = [input(1, "ADM-OSC")];
        tc.inputs[0].enabled = false;
        const out = Engine.createOutput("p", "127.0.0.1", 9999, "probe");
        Engine.setDeviceParams(out, { gain: "3.5", stray: 1 }, "output");
        compare(out.params.gain, 3.5, "coerced to the declared type");
        compare(out.params.stray, 1, "undeclared keys are kept");
        Engine.saveConfiguration();

        const raw = appSettings.savedConfiguration;
        tc.outputs = [];
        tc.inputs = [];
        tc.routes = [];
        appSettings.savedConfiguration = raw;
        Engine.restoreConfiguration();
        const back = tc.outputs.filter(function (o) { return o.protocol === "probe"; })[0];
        compare(Engine.paramValues(back).gain, 3.5);
    }

    // With onParamsChanged the instance stays and sees the new values;
    // without it, it is rebuilt.
    function test_params_update_live_or_rebuild() {
        load("test://live", `module.exports = { apiVersion: 1, id: "live",
            params: [{ key: "k", type: "int", default: 1 }],
            createOutput: function (ctx) {
                const built = ++module.exports.builds;
                return {
                    onParamsChanged: function () { module.exports.seen = ctx.params.k; },
                    position: function (ev) { ctx.send("/k", [ctx.params.k, built]); }
                };
            },
            builds: 0 };`);
        load("test://rebuilt", `module.exports = { apiVersion: 1, id: "rebuilt",
            params: [{ key: "k", type: "int", default: 1 }],
            createOutput: function (ctx) {
                const built = ++module.exports.builds;
                return { position: function (ev) { ctx.send("/k", [ctx.params.k, built]); } };
            },
            builds: 0 };`);

        const inp = input(1, "ADM-OSC");
        const live = sink(10, "live"), rebuilt = sink(11, "rebuilt");
        world([inp], [live, rebuilt], [route(1, 10), route(1, 11)]);
        tc.outputs = [live, rebuilt];

        Engine.setDeviceParams(live, { k: 5 }, "output");
        Engine.setDeviceParams(rebuilt, { k: 5 }, "output");
        Engine.onInputValueReceived(inp, "/adm/obj/1/xyz", [0, 0, 0]);

        compare(live.sent[0].value, [5, 1], "same instance, new value");
        compare(Handlers.get("live").descriptor.seen, 5);
        compare(rebuilt.sent[0].value, [5, 2], "a second instance");
    }

    function test_param_coercion_data() {
        return [
            { tag: "int clamps",  spec: { key: "a", type: "int", min: 1, max: 4 }, value: "9", expected: 4 },
            { tag: "int junk",    spec: { key: "a", type: "int", default: 2 }, value: "x", expected: 2 },
            { tag: "real",        spec: { key: "a", type: "real" }, value: "0.25", expected: 0.25 },
            { tag: "bool",        spec: { key: "a", type: "bool" }, value: "true", expected: true },
            { tag: "enum valid",  spec: { key: "a", type: "enum", options: ["p", "q"] }, value: "q", expected: "q" },
            { tag: "enum junk",   spec: { key: "a", type: "enum", options: ["p", "q"] }, value: "z", expected: "p" },
            { tag: "string",      spec: { key: "a", type: "string", default: "d" }, value: undefined, expected: "d" }
        ];
    }
    function test_param_coercion(row) {
        const entry = { params: [row.spec] };
        const saved = row.value === undefined ? {} : { a: row.value };
        compare(Handlers.resolveParams(entry, saved).a, row.expected);
    }

    // ---------------------------------------------------------------- //
    // The template and error lines                                      //
    // ---------------------------------------------------------------- //

    function test_the_template_compiles_and_runs() {
        const src = Template.make("tpl-test", "Template test");
        verify(src.indexOf("__ID__") < 0 && src.indexOf("__NAME__") < 0, "placeholders filled");
        compare(load("test://tpl", src), "");
        const h = Handlers.get("tpl-test");
        compare(h.name, "Template test");
        verify(h.hasInput && h.hasOutput);

        // Its defaults: /obj/<n>/xyz, half-width 1, one-based.
        const inp = input(1, "tpl-test");
        const out = sink(10, "tpl-test");
        world([inp], [out], [route(1, 10)]);
        Engine.onInputValueReceived(inp, "/obj/4/xyz", [0.5, -0.25, 0]);
        compare(addresses(out), ["/obj/4/xyz"]);
        fuzzyCompare(out.sent[0].value[0], 0.5, 1e-6, "round trip through SpatGRIS units");
        fuzzyCompare(out.sent[0].value[1], -0.25, 1e-6);
    }

    function test_errors_point_at_the_script_line_data() {
        return [
            { tag: "syntax",  src: "// one\n// two\nlet x = ;\n", line: 3 },
            { tag: "at load", src: "\n\nnull.boom;\n", line: 3 },
            { tag: "line one", src: "module.exports = {", line: 2 }
        ];
    }
    function test_errors_point_at_the_script_line(row) {
        loadedUrls.push("test://lines");
        const err = Handlers.loadScript("test://lines", row.src);
        verify(err !== "");
        const rec = Handlers.scripts().filter(function (s) { return s.url === "test://lines"; })[0];
        compare(rec.line, row.line, err);
        verify(err.indexOf("(line " + row.line + ")") >= 0, err);
    }

    function test_runtime_errors_name_the_line() {
        load("test://rtline", "module.exports = { apiVersion: 1, id: 'rtline',\n"
             + "  createOutput: function () { return {\n"
             + "    position: function () { null.boom; } }; } };");
        const inp = input(1, "ADM-OSC");
        const out = sink(10, "rtline");
        world([inp], [out], [route(1, 10)]);
        Engine.onInputValueReceived(inp, "/adm/obj/1/xyz", [0, 0, 0]);
        verify(out.handlerError.indexOf("(line 3)") >= 0, out.handlerError);
    }

    // ---------------------------------------------------------------- //
    // Inline scripts (the editor)                                       //
    // ---------------------------------------------------------------- //

    function test_a_new_inline_script_starts_from_the_template() {
        const url = Engine.newInlineScript();
        compare(url, "inline:script-1");
        compare(Handlers.get("script-1").name, "Script 1");
        compare(JSON.parse(appSettings.handlerScripts), [url], "listed for the next start");
        compare(JSON.parse(appSettings.inlineScripts)[url], Template.make("script-1", "Script 1"));

        const second = Engine.newInlineScript();
        compare(second, "inline:script-2", "the next one gets a free id");
    }

    function test_applying_an_edit_replaces_the_handler() {
        const url = Engine.newInlineScript();
        const edited = Template.make("script-1", "Renamed");
        let result = null;
        Engine.applyScript(url, edited, function (r) { result = r; });
        compare(result.error, "");
        verify(result.saved);
        compare(Handlers.get("script-1").name, "Renamed");
        compare(JSON.parse(appSettings.inlineScripts)[url], edited);
    }

    // A broken edit is kept, so no work is lost, and the running version
    // keeps running.
    function test_a_broken_edit_is_saved_but_not_applied() {
        const url = Engine.newInlineScript();
        const out = sink(10, "script-1");
        const inp = input(1, "ADM-OSC");
        world([inp], [out], [route(1, 10)]);

        let result = null;
        Engine.applyScript(url, "module.exports = {\n  apiVersion: 1,\n  id: oops oops\n};", function (r) { result = r; });
        verify(result.error !== "");
        compare(result.line, 3);
        verify(result.saved);
        verify(JSON.parse(appSettings.inlineScripts)[url].indexOf("oops") >= 0);

        verify(Handlers.get("script-1") !== null, "the previous version is still registered");
        Engine.onInputValueReceived(inp, "/adm/obj/2/xyz", [0, 0, 0]);
        compare(addresses(out), ["/obj/2/xyz"], "and still routes");
    }

    function test_inline_scripts_come_back_on_restart() {
        const url = Engine.newInlineScript();
        Engine.applyScript(url, Template.make("script-1", "Kept"), function () {});
        const urls = appSettings.handlerScripts, sources = appSettings.inlineScripts;

        // A fresh start: nothing registered, the settings as saved.
        Handlers.removeScript(url);
        compare(Handlers.get("script-1"), null);
        appSettings.handlerScripts = urls;
        appSettings.inlineScripts = sources;
        Engine.loadSavedScripts();
        compare(Handlers.get("script-1").name, "Kept");
    }

    function test_removing_an_inline_script_deletes_its_source() {
        const url = Engine.newInlineScript();
        Engine.removeScript(url);
        compare(Handlers.get("script-1"), null);
        compare(JSON.parse(appSettings.inlineScripts), {});
        compare(JSON.parse(appSettings.handlerScripts), []);
    }

    function test_reading_an_inline_source() {
        const url = Engine.newInlineScript();
        let got = null, error = null;
        Engine.readSource(url, function (s, e) { got = s; error = e; });
        compare(error, "");
        compare(got, Template.make("script-1", "Script 1"));
        Engine.readSource("inline:nothing", function (s, e) { error = e; });
        verify(error !== "");
    }

    // Editing a script that lives in a file writes the file. Needs
    // QML_XHR_ALLOW_FILE_READ=1 and QML_XHR_ALLOW_FILE_WRITE=1, as the app sets.
    function test_applying_a_file_script_writes_the_file() {
        const dir = StandardPaths.writableLocation(StandardPaths.TempLocation);
        // One fixed name, overwritten each run: XMLHttpRequest cannot delete files.
        const url = dir.toString() + "/spm-handler-test.js";
        const src = Template.make("file-test", "File test");

        let result = null;
        Engine.applyScript(url, src, function (r) { result = r; });
        tryVerify(function () { return result !== null; }, Engine.FILE_TIMEOUT_MS + 3000,
                  "a write Qt refuses still reports back");
        if (!result.saved)
            skip("file writes are not allowed in this environment: " + result.error);
        loadedUrls.push(url);
        compare(result.error, "");
        compare(Handlers.get("file-test").name, "File test");

        let back = null;
        Engine.readSource(url, function (s) { back = s; });
        tryVerify(function () { return back !== null; }, Engine.FILE_TIMEOUT_MS + 3000);
        compare(back, src, "the file holds what was applied");
        // Leave nothing behind.
        const x = new XMLHttpRequest();
        x.open("PUT", url);
        x.send("");
    }

    // ---------------------------------------------------------------- //
    // Logging                                                           //
    // ---------------------------------------------------------------- //

    function test_logging_follows_the_settings_and_the_monitor() {
        appSettings.logSentMessages = true;
        tc.monitorActive = false;
        Engine.updateLogging();
        verify(!Engine.g_logOut, "nothing is formatted while the monitor is hidden");
        tc.monitorActive = true;
        Engine.updateLogging();
        verify(Engine.g_logOut);
        verify(!Engine.g_logIn);
        appSettings.logSentMessages = false;
        tc.monitorActive = false;
        Engine.updateLogging();
    }

    // ---------------------------------------------------------------- //
    // Benchmarks                                                        //
    // ---------------------------------------------------------------- //

    function benchWorld(protocol) {
        const inp = input(1, protocol);
        const outs = [sink(10, "SpatGRIS"), sink(11, "ADM-OSC"), sink(12, "SPAT Revolution")];
        // A socket that discards, like a real one, without recording.
        for (let o of outs) o.udp = { osc: function () {} };
        world([inp], outs, [route(1, 10), route(1, 11, 16), route(1, 12)]);
        return inp;
    }

    // 1000 ADM position updates over 64 sources, fanned out to three outputs.
    function benchmark_adm_to_three_outputs() {
        const inp = benchWorld("ADM-OSC");
        const addrs = [];
        for (let i = 0; i < 64; i++) addrs.push("/adm/obj/" + (i + 1) + "/xyz");
        const v = [0.1, 0.2, 0.3];
        for (let i = 0; i < 1000; i++)
            Engine.onInputValueReceived(inp, addrs[i & 63], v);
    }

    function benchmark_spatgris_to_three_outputs() {
        const inp = benchWorld("SpatGRIS");
        const v = ["deg", 1, 30, 10, 1, 0, 0];
        for (let i = 0; i < 1000; i++) {
            v[1] = (i & 63) + 1;
            Engine.onInputValueReceived(inp, "/spat/serv", v);
        }
    }
}
