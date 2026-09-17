// SPDX-License-Identifier: GPL-3.0-or-later
// © Société des arts technologiques
//
// Stateful engine tests: the message path, device lifecycle and persistence.
//
// Engine.js is not a `.pragma library`, so its free variables resolve against
// the QML context that imports it. Declaring them here hands the engine a
// complete fake world -- stub sockets that record what was sent, a stub
// Protocols, a stub settings object -- and lets the parts that tst_engine.qml
// cannot reach be driven directly.
import QtQuick
import QtTest
import "../qml/spm/Engine.js" as Engine

TestCase {
    id: tc
    name: "dispatch"

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
    }

    // Records every bind so a leaked or revived socket is visible.
    property var opened: []
    property var closed: []

    // `Protocols` is injected by ossia/score as a global; qmltestrunner has no
    // such thing, and a QML property cannot be named with a capital, so it goes
    // on the JS global object where the engine's unqualified lookup finds it.
    function initTestCase() {
        // An indirect `this` is the JS global object; Qt 6.4's V4 has no
        // `globalThis`.
        var g = (function () { return this; })();
        g.Protocols = {
            osc: function (cfg) {
                return { processMessage: function () {} };
            },
            inboundUDP: function (cfg) {
                var port = cfg.Transport.Port;
                tc.opened.push(port);
                return { port: port, close: function () { tc.closed.push(port); } };
            },
            outboundUDP: function (cfg) {
                return { osc: function () {}, close: function () {} };
            }
        };
    }

    function reset() {
        tc.inputs = [];
        tc.outputs = [];
        tc.routes = [];
        tc.opened = [];
        tc.closed = [];
        appSettings.savedConfiguration = "";
        appSettings.savedOutputDevices = "[]";
        appSettings.listenPort = 18032;
    }

    // The engine calls these back; the views normally supply them.
    function syncCurrentInput() {}
    ListModel { id: inputListModel }
    ListModel { id: outputListModel }
    ListModel { id: routeListModel }
    ListModel { id: matrixModel }

    function sink(id, name, protocol) {
        var out = {
            id: id, name: name, protocol: protocol, sent: [],
            udp: null
        };
        out.udp = { osc: function (a, v) { out.sent.push({ address: a, value: v }); } };
        return out;
    }

    function admInput(id) {
        return { id: id, name: "in" + id, protocol: "ADM-OSC",
                 enabled: true, listening: true, error: "",
                 admState: {}, spatState: {}, udp: null, osc: null };
    }

    // ---------------------------------------------------------------- //
    // The per-source accumulator must not go cold                       //
    // ---------------------------------------------------------------- //

    // ADM and SPAT send one parameter per message and the parser accumulates
    // them per source. If parsing is skipped while nothing is routed, the
    // first message after a route comes back on carries spec defaults for
    // every axis the sender did not just write, and the source jumps.
    function test_accumulator_stays_warm_while_nothing_is_routed() {
        reset();
        var out = sink(10, "o", "ADM-OSC");
        var inp = admInput(1);
        tc.inputs = [inp];
        tc.outputs = [out];
        tc.routes = [{ inputId: 1, outputId: 10, enabled: false,
                       sourceOffset: 0, srcMin: null, srcMax: null }];
        Engine.reindexRoutes();

        // Goes nowhere, but the position must be recorded.
        Engine.onInputValueReceived(inp, "/adm/obj/1/xyz", [0.5, 0.6, 0.7]);
        compare(out.sent.length, 0, "a disabled route forwards nothing");

        tc.routes[0].enabled = true;
        Engine.reindexRoutes();
        Engine.onInputValueReceived(inp, "/adm/obj/1/x", [0.9]);

        var xyz = out.sent.filter(function (m) { return m.address === "/adm/obj/1/xyz"; });
        compare(xyz.length, 1, "the update is forwarded once the route is on");
        // Cartesian is scaled into ADM's normalized range on the way out.
        var k = 1.6666667;
        fuzzyCompare(xyz[0].value[0], 0.9 / k, 1e-6, "x is the value just written");
        fuzzyCompare(xyz[0].value[1], 0.6 / k, 1e-6, "y survived the quiet period");
        fuzzyCompare(xyz[0].value[2], 0.7 / k, 1e-6, "z survived the quiet period");
    }

    // An input with no routes at all is the same situation.
    function test_accumulator_stays_warm_with_no_routes_at_all() {
        reset();
        var out = sink(10, "o", "ADM-OSC");
        var inp = admInput(1);
        tc.inputs = [inp];
        tc.outputs = [out];
        tc.routes = [];
        Engine.reindexRoutes();

        Engine.onInputValueReceived(inp, "/adm/obj/2/xyz", [0.1, 0.2, 0.3]);
        tc.routes = [{ inputId: 1, outputId: 10, enabled: true,
                       sourceOffset: 0, srcMin: null, srcMax: null }];
        Engine.reindexRoutes();
        Engine.onInputValueReceived(inp, "/adm/obj/2/z", [0.8]);

        var xyz = out.sent.filter(function (m) { return m.address === "/adm/obj/2/xyz"; });
        compare(xyz.length, 1);
        var k = 1.6666667;
        fuzzyCompare(xyz[0].value[0], 0.1 / k, 1e-6);
        fuzzyCompare(xyz[0].value[1], 0.2 / k, 1e-6);
        fuzzyCompare(xyz[0].value[2], 0.8 / k, 1e-6);
    }

    // ---------------------------------------------------------------- //
    // Persistence                                                       //
    // ---------------------------------------------------------------- //

    // A truncated or corrupt blob must not be migrated over: migrateFromV1
    // ends in saveConfiguration(), which would replace the only copy of the
    // user's real setup with a v1-derived guess.
    function test_corrupt_configuration_is_not_overwritten() {
        reset();
        var corrupt = '{"version":2,"inputs":[{"id":1,"na';
        appSettings.savedConfiguration = corrupt;
        appSettings.savedOutputDevices =
            '[{"name":"legacy","host":"1.2.3.4","port":9999,"type":"SpatGRIS","active":true}]';

        Engine.restoreConfiguration();

        compare(appSettings.savedConfiguration, corrupt,
                "the stored bytes are left alone");
        compare(tc.inputs.length, 1, "the app still comes up usable");
        compare(tc.outputs.length, 0,
                "and does not resurrect the stale v1 outputs over the top");
    }

    // A real first run still migrates.
    function test_first_run_migrates_from_v1() {
        reset();
        appSettings.listenPort = 18042;
        appSettings.savedOutputDevices =
            '[{"name":"legacy","host":"1.2.3.4","port":9999,"type":"SpatGRIS",'
            + '"active":false,"sourceIndexOffset":3}]';

        Engine.restoreConfiguration();

        compare(tc.inputs.length, 1);
        compare(tc.inputs[0].port, 18042, "the old listen port carries over");
        compare(tc.outputs.length, 1);
        compare(tc.routes.length, 1);
        compare(tc.routes[0].enabled, false, "an inactive output is a disabled route");
        compare(tc.routes[0].sourceOffset, 3, "the offset moves onto the route");
        verify(appSettings.savedConfiguration !== "", "and a v2 blob is written");
    }

    // Math.max against an undefined id yields NaN, and NaN never compares
    // equal to itself: every later id would be unfindable and no route could
    // ever be matched again.
    function test_a_device_without_an_id_cannot_poison_the_counter() {
        reset();
        appSettings.savedConfiguration = JSON.stringify({
            version: 2,
            inputs: [{ name: "no id", port: 18032, enabled: true },
                     { id: 4, name: "fine", port: 18033, enabled: true }],
            outputs: [],
            routes: []
        });

        Engine.restoreConfiguration();

        compare(tc.inputs.length, 1, "the unusable entry is skipped");
        compare(tc.inputs[0].id, 4);

        var dev = Engine.createOutput("o", "127.0.0.1", 9000, "SpatGRIS");
        verify(isFinite(dev.id), "the next id is still a number, not NaN");
        compare(dev.id, 5);
        verify(Engine.findOutput(dev.id) !== null, "and it can be found again");
    }

    function test_duplicate_ids_are_skipped() {
        reset();
        appSettings.savedConfiguration = JSON.stringify({
            version: 2,
            inputs: [{ id: 1, name: "a", port: 18032, enabled: true }],
            outputs: [{ id: 2, name: "x", protocol: "SpatGRIS", host: "h", port: 1 },
                      { id: 2, name: "y", protocol: "SpatGRIS", host: "h", port: 2 }],
            routes: []
        });

        Engine.restoreConfiguration();
        compare(tc.outputs.length, 1, "the second claimant is dropped");
        compare(tc.outputs[0].name, "x");
    }

    // A route naming a device that was refused would otherwise sit in the
    // array and be written straight back out on the next save.
    function test_routes_to_missing_devices_are_dropped() {
        reset();
        appSettings.savedConfiguration = JSON.stringify({
            version: 2,
            inputs: [{ id: 1, name: "a", port: 18032, enabled: true }],
            outputs: [{ id: 2, name: "x", protocol: "SpatGRIS", host: "h", port: 1 }],
            routes: [{ inputId: 1, outputId: 2, enabled: true, sourceOffset: 0 },
                     { inputId: 1, outputId: 99, enabled: true, sourceOffset: 0 },
                     { inputId: 99, outputId: 2, enabled: true, sourceOffset: 0 }]
        });

        Engine.restoreConfiguration();
        compare(tc.routes.length, 1);
        compare(tc.routes[0].outputId, 2);
    }

    // ---------------------------------------------------------------- //
    // Input lifecycle                                                   //
    // ---------------------------------------------------------------- //

    function test_a_port_already_held_is_refused_and_reported() {
        reset();
        Engine.createInput("a", 18032, "Auto");
        var b = Engine.createInput("b", 18033, "Auto");

        Engine.updateInput(b.id, { port: 18032 });

        compare(b.port, 18033, "the port is not taken");
        verify(b.error.indexOf("18032") >= 0, "and the refusal says which port");
    }

    function test_an_unparseable_port_is_reported() {
        reset();
        var a = Engine.createInput("a", 18032, "Auto");
        Engine.updateInput(a.id, { port: "not a port" });
        compare(a.port, 18032);
        compare(a.error, "Invalid port");
    }

    function test_a_free_port_is_accepted_and_clears_the_error() {
        reset();
        var a = Engine.createInput("a", 18032, "Auto");
        a.error = "something earlier";
        Engine.updateInput(a.id, { port: 18099 });
        compare(a.port, 18099);
        compare(a.error, "");
    }

    // Removing an input must take its routes with it, or the dispatch index
    // would keep resolving them.
    function test_removing_an_input_drops_its_routes() {
        reset();
        var a = Engine.createInput("a", 18032, "Auto");
        var o = Engine.createOutput("o", "127.0.0.1", 9000, "SpatGRIS");
        Engine.setRoute(a.id, o.id, { enabled: true });
        compare(tc.routes.length, 1);

        Engine.removeInput(a.id);
        compare(tc.routes.length, 0);
        compare(tc.inputs.length, 0);
    }

    function test_removing_an_output_drops_its_routes_and_closes_it() {
        reset();
        var a = Engine.createInput("a", 18032, "Auto");
        var o = Engine.createOutput("o", "127.0.0.1", 9000, "SpatGRIS");
        Engine.setRoute(a.id, o.id, { enabled: true });

        Engine.removeOutput(o.id);
        compare(tc.routes.length, 0);
        compare(tc.outputs.length, 0);
        compare(o.udp, null, "the socket is released");
    }
}
