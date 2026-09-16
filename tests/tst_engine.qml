// SPDX-License-Identifier: GPL-3.0-or-later
// © Société des arts technologiques
//
// Characterization tests for the protocol conversion table in Engine.js.
//
// These pin the *current* wire output of every parse and map path so the
// routing rework (ids, routes, multi-input, source-id ranges) can be proven
// not to have moved a source. Where the existing behaviour is surprising, the
// test says so rather than "correcting" it — the point is to detect change,
// not to assert an opinion.
//
// Run:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/
//
// Only the pure parse/map functions are exercised. Everything below
// `----- Output device lifecycle -----` in Engine.js touches the QML root
// context (Protocols, appSettings, outputDevices) and is covered by the
// visual pass instead.
import QtQuick
import QtTest
import "../qml/spm/Engine.js" as Engine

TestCase {
    id: tc
    name: "engine"

    readonly property real eps: 1e-9
    readonly property real halfPi: Math.PI / 2
    // sg_constants.hpp:71 — the cartesian clamp SpatGRIS applies.
    readonly property real mbap: 1.6666667

    // parseADMInput accumulates onto the input device it was handed, so a
    // fresh one per test is all the isolation needed.
    function newInput(protocol) {
        return { id: 1, name: "test", protocol: protocol || "Auto", admState: {} };
    }

    function checkMsg(msg, address, values) {
        compare(msg.address, address, "address");
        var v = Array.isArray(msg.value) ? msg.value : [msg.value];
        compare(v.length, values.length, "arity of " + address);
        for (var i = 0; i < values.length; i++) {
            if (typeof values[i] === "number")
                fuzzyCompare(v[i], values[i], tc.eps, address + "[" + i + "]");
            else
                compare(v[i], values[i], address + "[" + i + "]");
        }
    }

    // ---------------------------------------------------------------- //
    // parseSpatGRISInput — /spat/serv                                   //
    // ---------------------------------------------------------------- //

    function test_spatgris_rejects_empty_data() {
        return [
            { tag: "null",     value: null },
            { tag: "empty",    value: [] },
            { tag: "one-elem", value: ["pol"] }
        ];
    }
    function test_spatgris_rejects_empty(row) {
        compare(Engine.parseSpatGRISInput(row.value), null);
    }

    // Legacy wire form: [sourceIndex, az, el, hspan, vspan, radius, reserved],
    // 0-based index, polar in radians, elevation measured from the zenith.
    function test_spatgris_legacy_needs_seven_args() {
        compare(Engine.parseSpatGRISInput([0, 0.1, 0.2, 0.3, 0.4, 0.5]), null);
    }

    function test_spatgris_legacy_normalizes_to_pol() {
        var n = Engine.parseSpatGRISInput([6, 0.5, 0.25, 0.3, 0.4, 1.5, 0]);
        compare(n.command, "pol");
        // 0-based on the wire, 1-based internally.
        compare(n.sourceIndex, 7);
        fuzzyCompare(n.args[0], 0.5, eps, "azimuth passes through");
        fuzzyCompare(n.args[1], halfPi - 0.25, eps, "colatitude -> elevation");
        fuzzyCompare(n.args[2], 1.5, eps, "radius comes from value[5]");
        fuzzyCompare(n.args[3], 0.15, eps, "hspan halved");
        fuzzyCompare(n.args[4], 0.8, eps, "vspan doubled");
    }

    // The raw payload is kept so a SpatGRIS output can re-emit the legacy form
    // verbatim: SpatGRIS routes legacy through a cylindrical conversion and
    // "pol" through a spherical one, so rewriting would move the source.
    function test_spatgris_legacy_keeps_raw_payload() {
        var n = Engine.parseSpatGRISInput([6, 0.5, 0.25, 0.3, 0.4, 1.5, 0]);
        compare(n.legacyArgs.length, 6);
        compare(n.legacyArgs[0], 0.5);
        compare(n.legacyArgs[4], 1.5);
    }

    function test_spatgris_modern_forms_data() {
        return [
            { tag: "pol", value: ["pol", 3, 0.5, 0.25, 1.0, 0.1, 0.2],
              command: "pol", index: 3, argc: 5 },
            { tag: "deg", value: ["deg", 7, -90.0, 0.0, 1.0, 0.0, 0.0],
              command: "deg", index: 7, argc: 5 },
            { tag: "car", value: ["car", 2, 0.1, 0.2, 0.3, 0.4, 0.5],
              command: "car", index: 2, argc: 5 },
            { tag: "clr", value: ["clr", 4], command: "clr", index: 4, argc: 0 },
            { tag: "alg", value: ["alg", 1, "dome"], command: "alg", index: 1, argc: 1 }
        ];
    }
    function test_spatgris_modern_forms(row) {
        var n = Engine.parseSpatGRISInput(row.value);
        compare(n.command, row.command);
        compare(n.sourceIndex, row.index);
        compare(n.args.length, row.argc);
        verify(n.legacyArgs === undefined, "modern form carries no legacy payload");
    }

    // A command whose second element is not a number has no source index.
    // Downstream this reaches mapForSpatGRIS's catch-all with idx === -1.
    function test_spatgris_sourceless_command_indexes_minus_one() {
        var n = Engine.parseSpatGRISInput(["reset", "all"]);
        compare(n.command, "reset");
        compare(n.sourceIndex, -1);
        compare(n.args.length, 0);
    }

    // ---------------------------------------------------------------- //
    // parseADMInput — /adm/obj/{n}/…                                    //
    // ---------------------------------------------------------------- //

    function test_adm_rejects_addresses_data() {
        return [
            { tag: "listener",  address: "/adm/lis/azim" },
            { tag: "env",       address: "/adm/env/size" },
            { tag: "wildcard",  address: "/adm/obj/*/azim" },
            { tag: "too-deep",  address: "/adm/obj/1/foo/bar" },
            { tag: "not-adm",   address: "/spat/serv" }
        ];
    }
    function test_adm_rejects_addresses(row) {
        compare(Engine.parseADMInput(newInput(), row.address, [1.0]), null);
    }

    // gain/mute/name/dref/dmax have no equivalent in the internal model; they
    // return null here and are picked up by the raw-forwarding path instead.
    function test_adm_unmodelled_params_data() {
        return [
            { tag: "gain", param: "gain" },
            { tag: "mute", param: "mute" },
            { tag: "name", param: "name" },
            { tag: "dmax", param: "dmax" }
        ];
    }
    function test_adm_unmodelled_params(row) {
        compare(Engine.parseADMInput(newInput(), "/adm/obj/90/" + row.param, [1.0]), null);
    }

    // ADM azimuth is +90 = left; SpatGRIS is -90 = left. Sign flips.
    // ADM has no vertical extent, so vspan is always 0.
    function test_adm_aed_emits_degrees() {
        var n = Engine.parseADMInput(newInput(), "/adm/obj/10/aed", [30.0, 15.0, 0.8]);
        compare(n.command, "deg");
        compare(n.sourceIndex, 10);
        fuzzyCompare(n.args[0], -30.0, eps, "azimuth sign flipped");
        fuzzyCompare(n.args[1], 15.0, eps, "elevation unchanged");
        fuzzyCompare(n.args[2], 0.8, eps, "distance unchanged");
        fuzzyCompare(n.args[3], 0.0, eps, "width defaults to 0");
        fuzzyCompare(n.args[4], 0.0, eps, "no vertical extent in ADM");
    }

    // ADM sends per-parameter messages, so state accumulates per source and a
    // complete command is emitted on every update.
    function test_adm_accumulates_polar_components() {
        var inp = newInput();
        var a = Engine.parseADMInput(inp, "/adm/obj/11/azim", [45.0]);
        compare(a.command, "deg");
        fuzzyCompare(a.args[0], -45.0, eps);
        fuzzyCompare(a.args[1], 0.0, eps, "elevation still at default");
        fuzzyCompare(a.args[2], 1.0, eps, "distance defaults to the unit sphere");

        var b = Engine.parseADMInput(inp, "/adm/obj/11/elev", [20.0]);
        fuzzyCompare(b.args[0], -45.0, eps, "azimuth retained");
        fuzzyCompare(b.args[1], 20.0, eps);

        var c = Engine.parseADMInput(inp, "/adm/obj/11/dist", [0.5]);
        fuzzyCompare(c.args[0], -45.0, eps);
        fuzzyCompare(c.args[1], 20.0, eps);
        fuzzyCompare(c.args[2], 0.5, eps);
    }

    function test_adm_xyz_emits_cartesian() {
        var n = Engine.parseADMInput(newInput(), "/adm/obj/12/xyz", [0.1, 0.2, 0.3]);
        compare(n.command, "car");
        compare(n.sourceIndex, 12);
        fuzzyCompare(n.args[0], 0.1, eps);
        fuzzyCompare(n.args[1], 0.2, eps);
        fuzzyCompare(n.args[2], 0.3, eps);
        fuzzyCompare(n.args[4], 0.0, eps);
    }

    function test_adm_accumulates_cartesian_components() {
        var inp = newInput();
        Engine.parseADMInput(inp, "/adm/obj/13/xyz", [0.1, 0.2, 0.3]);
        var n = Engine.parseADMInput(inp, "/adm/obj/13/x", [0.9]);
        compare(n.command, "car");
        fuzzyCompare(n.args[0], 0.9, eps, "x overwritten");
        fuzzyCompare(n.args[1], 0.2, eps, "y retained");
        fuzzyCompare(n.args[2], 0.3, eps, "z retained");
    }

    function test_adm_xy_leaves_z_alone() {
        var inp = newInput();
        Engine.parseADMInput(inp, "/adm/obj/14/xyz", [0.1, 0.2, 0.7]);
        var n = Engine.parseADMInput(inp, "/adm/obj/14/xy", [0.4, 0.5]);
        fuzzyCompare(n.args[0], 0.4, eps);
        fuzzyCompare(n.args[1], 0.5, eps);
        fuzzyCompare(n.args[2], 0.7, eps, "z untouched by /xy");
    }

    // The last coordinate family written decides which command comes out.
    function test_adm_last_family_written_wins() {
        var inp = newInput();
        Engine.parseADMInput(inp, "/adm/obj/15/xyz", [0.1, 0.2, 0.3]);
        compare(Engine.parseADMInput(inp, "/adm/obj/15/azim", [10.0]).command, "deg");
        compare(Engine.parseADMInput(inp, "/adm/obj/15/y", [0.4]).command, "car");
    }

    // Width alone does not switch coordinate mode.
    function test_adm_width_keeps_current_mode() {
        var inp = newInput();
        Engine.parseADMInput(inp, "/adm/obj/16/aed", [30.0, 0.0, 1.0]);
        var n = Engine.parseADMInput(inp, "/adm/obj/16/w", [0.25]);
        compare(n.command, "deg", "still polar");
        fuzzyCompare(n.args[3], 0.25, eps, "width carried into the command");
    }

    function test_adm_short_payloads_rejected_data() {
        return [
            { tag: "aed", address: "/adm/obj/17/aed", value: [1.0, 2.0] },
            { tag: "xyz", address: "/adm/obj/17/xyz", value: [1.0, 2.0] },
            { tag: "xy",  address: "/adm/obj/17/xy",  value: [1.0] },
            { tag: "x",   address: "/adm/obj/17/x",   value: [] }
        ];
    }
    function test_adm_short_payloads_rejected(row) {
        compare(Engine.parseADMInput(newInput(), row.address, row.value), null);
    }

    // ---------------------------------------------------------------- //
    // mapForSpatGRIS — /spat/serv out                                   //
    // ---------------------------------------------------------------- //

    // A legacy input goes back out legacy and untouched. idx is 1-based
    // internally (plus any offset); the legacy wire form is 0-based.
    function test_map_spatgris_legacy_round_trips() {
        var norm = Engine.parseSpatGRISInput([6, 0.5, 0.25, 0.3, 0.4, 1.5, 0]);
        var out = Engine.mapForSpatGRIS("pol", norm.sourceIndex, norm.args, norm);
        compare(out.length, 1);
        checkMsg(out[0], "/spat/serv", [6, 0.5, 0.25, 0.3, 0.4, 1.5, 0]);
    }

    function test_map_spatgris_legacy_applies_offset_zero_based() {
        var norm = Engine.parseSpatGRISInput([6, 0.5, 0.25, 0.3, 0.4, 1.5, 0]);
        // sourceIndex 7 + an offset of 10 => wire index 16.
        var out = Engine.mapForSpatGRIS("pol", 17, norm.args, norm);
        compare(out[0].value[0], 16);
    }

    function test_map_spatgris_passes_coordinates_verbatim_data() {
        return [
            { tag: "pol", command: "pol" },
            { tag: "deg", command: "deg" },
            { tag: "car", command: "car" }
        ];
    }
    function test_map_spatgris_passes_coordinates_verbatim(row) {
        var out = Engine.mapForSpatGRIS(row.command, 3, [1, 2, 3, 4, 5], null);
        compare(out.length, 1);
        checkMsg(out[0], "/spat/serv", [row.command, 3, 1, 2, 3, 4, 5]);
    }

    function test_map_spatgris_short_coordinates_drop() {
        compare(Engine.mapForSpatGRIS("pol", 3, [1, 2, 3], null).length, 0);
    }

    function test_map_spatgris_clr() {
        var out = Engine.mapForSpatGRIS("clr", 5, [], null);
        checkMsg(out[0], "/spat/serv", ["clr", 5]);
    }

    function test_map_spatgris_alg() {
        var out = Engine.mapForSpatGRIS("alg", 5, ["dome"], null);
        checkMsg(out[0], "/spat/serv", ["alg", 5, "dome"]);
        compare(Engine.mapForSpatGRIS("alg", 5, [], null).length, 0);
    }

    // SpatGRIS speaks /spat/serv natively and supports commands this app does
    // not model (sg_OscInput.cpp:186-193), so unknown ones are forwarded.
    function test_map_spatgris_forwards_unknown_commands() {
        var out = Engine.mapForSpatGRIS("reset", 2, ["all"], null);
        checkMsg(out[0], "/spat/serv", ["reset", 2, "all"]);
    }

    function test_map_spatgris_drops_non_string_commands_data() {
        return [
            { tag: "empty",  command: "" },
            { tag: "number", command: 42 },
            { tag: "null",   command: null }
        ];
    }
    function test_map_spatgris_drops_non_string_commands(row) {
        compare(Engine.mapForSpatGRIS(row.command, 1, [], null).length, 0);
    }

    // ---------------------------------------------------------------- //
    // mapForADM — /adm/obj/{n}/… out                                    //
    // ---------------------------------------------------------------- //

    // Packed /aed per the spec's atomicity recommendation. Azimuth flips sign
    // on the way out, elevation does not. /w rides along as a scalar.
    function test_map_adm_polar() {
        var out = Engine.mapForADM("pol", 4, [Math.PI / 2, Math.PI / 6, 0.8, 0.25, 0.9]);
        compare(out.length, 2);
        checkMsg(out[0], "/adm/obj/4/aed", [-90.0, 30.0, 0.8]);
        checkMsg(out[1], "/adm/obj/4/w", [0.25]);
    }

    function test_map_adm_degrees_round_trip() {
        var out = Engine.mapForADM("deg", 4, [-90.0, 30.0, 0.8, 0.25, 0.0]);
        // deg -> rad on the way in, rad -> deg with a sign flip on the way out.
        checkMsg(out[0], "/adm/obj/4/aed", [90.0, 30.0, 0.8]);
    }

    // SpatGRIS cartesian is the MBAP extended field (+-1.6666667); ADM-OSC is
    // normalized +-1. Scaling rather than letting the receiver clamp, which
    // would collapse everything past 60% of full scale onto the wall.
    function test_map_adm_cartesian_scales_into_normalized_range() {
        var out = Engine.mapForADM("car", 9, [mbap, -mbap, mbap / 2, 0.5, 0.0]);
        compare(out.length, 2);
        checkMsg(out[0], "/adm/obj/9/xyz", [1.0, -1.0, 0.5]);
        checkMsg(out[1], "/adm/obj/9/w", [0.5]);
    }

    function test_map_adm_clr_is_packed_xyz() {
        checkMsg(Engine.mapForADM("clr", 3, [])[0], "/adm/obj/3/xyz", [0, 0, 0]);
    }

    // ADM has no algorithm concept.
    function test_map_adm_drops_alg() {
        compare(Engine.mapForADM("alg", 3, ["dome"]).length, 0);
    }

    function test_map_adm_short_coordinates_drop_data() {
        return [
            { tag: "pol", command: "pol" },
            { tag: "deg", command: "deg" },
            { tag: "car", command: "car" }
        ];
    }
    function test_map_adm_short_coordinates_drop(row) {
        compare(Engine.mapForADM(row.command, 1, [1, 2, 3]).length, 0);
    }

    // ---------------------------------------------------------------- //
    // mapForSPAT — /source/{n}/… out                                    //
    // ---------------------------------------------------------------- //

    // SPAT keeps the SpatGRIS azimuth sign and takes radius as a percentage.
    // Spread is the mean of the two extents, also a percentage.
    function test_map_spat_polar() {
        var out = Engine.mapForSPAT("pol", 4, [Math.PI / 2, Math.PI / 6, 0.8, 0.2, 0.4]);
        compare(out.length, 2);
        checkMsg(out[0], "/source/4/aed", [90.0, 30.0, 80.0]);
        checkMsg(out[1], "/source/4/spread", [30.0]);
    }

    function test_map_spat_degrees() {
        var out = Engine.mapForSPAT("deg", 4, [-90.0, 30.0, 1.0, 0.0, 0.0]);
        checkMsg(out[0], "/source/4/aed", [-90.0, 30.0, 100.0]);
    }

    // Unlike ADM, SPAT cartesian is not rescaled.
    function test_map_spat_cartesian_unscaled() {
        var out = Engine.mapForSPAT("car", 9, [1.5, -0.5, 0.25, 0.2, 0.4]);
        checkMsg(out[0], "/source/9/xyz", [1.5, -0.5, 0.25]);
        checkMsg(out[1], "/source/9/spread", [30.0]);
    }

    function test_map_spat_clr() {
        checkMsg(Engine.mapForSPAT("clr", 3, [])[0], "/source/3/xyz", [0, 0, 0]);
    }

    function test_map_spat_alg_data() {
        return [
            { tag: "dome", arg: "dome", mode: "dome" },
            { tag: "cube", arg: "cube", mode: "panning" },
            { tag: "other", arg: "whatever", mode: "panning" }
        ];
    }
    function test_map_spat_alg(row) {
        checkMsg(Engine.mapForSPAT("alg", 3, [row.arg])[0], "/source/3/mode", [row.mode]);
    }

    function test_map_spat_alg_without_argument_drops() {
        compare(Engine.mapForSPAT("alg", 3, []).length, 0);
    }

    function test_map_spat_short_coordinates_drop_data() {
        return [
            { tag: "pol", command: "pol" },
            { tag: "deg", command: "deg" },
            { tag: "car", command: "car" }
        ];
    }
    function test_map_spat_short_coordinates_drop(row) {
        compare(Engine.mapForSPAT(row.command, 1, [1, 2, 3]).length, 0);
    }

    // ---------------------------------------------------------------- //
    // mapMessage dispatch                                               //
    // ---------------------------------------------------------------- //

    function test_dispatch_data() {
        return [
            { tag: "SpatGRIS",        type: "SpatGRIS",        address: "/spat/serv" },
            { tag: "ADM-OSC",         type: "ADM-OSC",         address: "/adm/obj/2/xyz" },
            { tag: "SPAT Revolution", type: "SPAT Revolution", address: "/source/2/xyz" }
        ];
    }
    function test_dispatch(row) {
        var out = Engine.mapMessage("car", 2, [0.1, 0.2, 0.3, 0.4, 0.5], row.type, null);
        verify(out.length > 0, row.type + " produced no messages");
        compare(out[0].address, row.address);
    }

    function test_dispatch_unknown_type_drops() {
        compare(Engine.mapMessage("car", 2, [1, 2, 3, 4, 5], "Nonexistent", null).length, 0);
    }


    // ---------------------------------------------------------------- //
    // Per-input ADM accumulator                                         //
    // ---------------------------------------------------------------- //

    // Two ADM senders each address their own source 1. A shared accumulator
    // would let one overwrite the other's coordinates.
    function test_adm_state_is_per_input() {
        var a = newInput();
        var b = newInput();

        Engine.parseADMInput(a, "/adm/obj/1/xyz", [0.1, 0.2, 0.3]);
        Engine.parseADMInput(b, "/adm/obj/1/xyz", [0.7, 0.8, 0.9]);

        // Touching one axis on A must leave A's other axes, and all of B, alone.
        var na = Engine.parseADMInput(a, "/adm/obj/1/x", [0.5]);
        fuzzyCompare(na.args[0], 0.5, eps);
        fuzzyCompare(na.args[1], 0.2, eps, "A keeps its own y");
        fuzzyCompare(na.args[2], 0.3, eps, "A keeps its own z");

        var nb = Engine.parseADMInput(b, "/adm/obj/1/y", [0.4]);
        fuzzyCompare(nb.args[0], 0.7, eps, "B keeps its own x");
        fuzzyCompare(nb.args[1], 0.4, eps);
        fuzzyCompare(nb.args[2], 0.9, eps, "B keeps its own z");
    }

    // The coordinate family is part of that per-input state too.
    function test_adm_mode_is_per_input() {
        var a = newInput();
        var b = newInput();
        Engine.parseADMInput(a, "/adm/obj/1/xyz", [0, 0, 0]);
        compare(Engine.parseADMInput(b, "/adm/obj/1/azim", [10.0]).command, "deg");
        compare(Engine.parseADMInput(a, "/adm/obj/1/x", [0.1]).command, "car",
                "A is still cartesian");
    }

    // ---------------------------------------------------------------- //
    // parseInput — per-input protocol selection                         //
    // ---------------------------------------------------------------- //

    function test_parse_input_auto_sniffs_both_protocols() {
        var inp = newInput("Auto");
        compare(Engine.parseInput(inp, "/spat/serv", ["clr", 2]).command, "clr");
        compare(Engine.parseInput(inp, "/adm/obj/5/xyz", [0, 0, 0]).command, "car");
        compare(Engine.parseInput(inp, "/other/address", [1]), null);
    }

    // A declared protocol ignores anything that is not its own, so two senders
    // on different ports cannot be confused for one another.
    function test_parse_input_declared_protocol_is_exclusive_data() {
        return [
            { tag: "spatgris-takes-own", protocol: "SpatGRIS",
              address: "/spat/serv", value: ["clr", 2], parsed: true },
            { tag: "spatgris-rejects-adm", protocol: "SpatGRIS",
              address: "/adm/obj/5/xyz", value: [0, 0, 0], parsed: false },
            { tag: "adm-takes-own", protocol: "ADM-OSC",
              address: "/adm/obj/5/xyz", value: [0, 0, 0], parsed: true },
            { tag: "adm-rejects-spatgris", protocol: "ADM-OSC",
              address: "/spat/serv", value: ["clr", 2], parsed: false }
        ];
    }
    function test_parse_input_declared_protocol_is_exclusive(row) {
        var got = Engine.parseInput(newInput(row.protocol), row.address, row.value);
        compare(got !== null, row.parsed);
    }

    // ---------------------------------------------------------------- //
    // routeAccepts — per-route source-id range filter                   //
    // ---------------------------------------------------------------- //

    function route(min, max) {
        return { enabled: true, sourceOffset: 0, srcMin: min, srcMax: max };
    }

    function test_route_unbounded_accepts_everything_data() {
        return [
            { tag: "null-null", route: { srcMin: null, srcMax: null } },
            { tag: "undefined", route: { } }
        ];
    }
    function test_route_unbounded_accepts_everything(row) {
        verify(Engine.routeAccepts(row.route, 1));
        verify(Engine.routeAccepts(row.route, 9999));
    }

    function test_route_range_is_inclusive_data() {
        return [
            { tag: "below",       index: 0,  accepted: false },
            { tag: "lower-bound", index: 1,  accepted: true },
            { tag: "inside",      index: 5,  accepted: true },
            { tag: "upper-bound", index: 8,  accepted: true },
            { tag: "above",       index: 9,  accepted: false }
        ];
    }
    function test_route_range_is_inclusive(row) {
        compare(Engine.routeAccepts(route(1, 8), row.index), row.accepted);
    }

    function test_route_half_open_ranges_data() {
        return [
            { tag: "min-only-below",  route: { srcMin: 17, srcMax: null }, index: 16, accepted: false },
            { tag: "min-only-at",     route: { srcMin: 17, srcMax: null }, index: 17, accepted: true },
            { tag: "min-only-far",    route: { srcMin: 17, srcMax: null }, index: 999, accepted: true },
            { tag: "max-only-inside", route: { srcMin: null, srcMax: 8 },  index: 1, accepted: true },
            { tag: "max-only-above",  route: { srcMin: null, srcMax: 8 },  index: 9, accepted: false }
        ];
    }
    function test_route_half_open_ranges(row) {
        compare(Engine.routeAccepts(row.route, row.index), row.accepted);
    }

    // A range filter is about sources. Commands that carry no source index --
    // /adm/lis, /adm/env, a global command, anything forwarded verbatim --
    // would otherwise be silenced on every filtered route.
    function test_route_sourceless_messages_bypass_the_filter() {
        verify(Engine.routeAccepts(route(1, 8), -1),
               "a sourceless message crosses a narrow range");
        verify(Engine.routeAccepts(route(100, 200), -1));
    }

    // The filter tests the incoming index; the offset is applied afterwards,
    // so the numbers a user types match the numbers on the sender.
    function test_route_filter_precedes_offset() {
        var r = route(1, 8);
        r.sourceOffset = 16;
        verify(Engine.routeAccepts(r, 8), "8 is in range before the offset");
        verify(!Engine.routeAccepts(r, 9), "9 is out of range despite landing at 25");
    }

    // ---------------------------------------------------------------- //
    // End-to-end: parse then map, the path a real message takes          //
    // ---------------------------------------------------------------- //

    // A ControlGRIS dome source at the extreme left, through each output.
    function test_end_to_end_controlgris_left_data() {
        return [
            { tag: "SpatGRIS", type: "SpatGRIS",
              address: "/spat/serv", first: "deg" },
            { tag: "ADM-OSC", type: "ADM-OSC",
              address: "/adm/obj/7/aed", first: 90.0 },
            { tag: "SPAT Revolution", type: "SPAT Revolution",
              address: "/source/7/aed", first: -90.0 }
        ];
    }
    function test_end_to_end_controlgris_left(row) {
        var norm = Engine.parseSpatGRISInput(["deg", 7, -90.0, 0.0, 1.0, 0.0, 0.0]);
        var out = Engine.mapMessage(norm.command, norm.sourceIndex, norm.args,
                                    row.type, norm);
        compare(out[0].address, row.address);
        if (typeof row.first === "number")
            fuzzyCompare(out[0].value[0], row.first, 1e-6);
        else
            compare(out[0].value[0], row.first);
    }

    // An ADM input feeding a SpatGRIS output: sign flips on the way in and
    // stays flipped on the way out.
    function test_end_to_end_adm_into_spatgris() {
        var norm = Engine.parseADMInput(newInput(), "/adm/obj/20/aed", [90.0, 0.0, 1.0]);
        var out = Engine.mapMessage(norm.command, norm.sourceIndex, norm.args,
                                    "SpatGRIS", norm);
        checkMsg(out[0], "/spat/serv", ["deg", 20, -90.0, 0.0, 1.0, 0.0, 0.0]);
    }

    // The per-output source index offset is applied before mapping.
    function test_end_to_end_offset_shifts_index() {
        var norm = Engine.parseSpatGRISInput(["car", 1, 0.1, 0.2, 0.3, 0.0, 0.0]);
        var out = Engine.mapMessage(norm.command, norm.sourceIndex + 16, norm.args,
                                    "ADM-OSC", norm);
        compare(out[0].address, "/adm/obj/17/xyz");
    }
}
