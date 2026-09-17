// SPDX-License-Identifier: GPL-3.0-or-later
// © Société des arts technologiques
//
// The route and scale summaries appear in the output rows, the matrix cells
// and the dialog headers. They are pinned here so those three cannot drift,
// and so the wording stays plain text.
//
// Needs the module on the import path:
//   qmltestrunner -import qml -input tests/tst_format.qml
import QtQuick
import QtTest
import spm

TestCase {
    name: "format"

    function test_range_data() {
        return [
            { tag: "unbounded",  min: -1, max: -1, expected: "all sources" },
            { tag: "both",       min: 1,  max: 8,  expected: "1 to 8" },
            { tag: "min-only",   min: 17, max: -1, expected: "17 and up" },
            { tag: "max-only",   min: -1, max: 8,  expected: "1 to 8" },
            { tag: "single",     min: 3,  max: 3,  expected: "3" }
        ];
    }
    function test_range(row) {
        compare(Format.range(row.min, row.max), row.expected);
    }

    function test_route_data() {
        return [
            { tag: "plain",          min: -1, max: -1, offset: 0,  expected: "all sources" },
            { tag: "ranged",         min: 1,  max: 8,  offset: 0,  expected: "1 to 8" },
            { tag: "offset",         min: -1, max: -1, offset: 16, expected: "all sources  +16" },
            { tag: "ranged-offset",  min: 1,  max: 8,  offset: 16, expected: "1 to 8  +16" }
        ];
    }
    function test_route(row) {
        compare(Format.route(row.min, row.max, row.offset), row.expected);
    }

    // The cell has no room to say "all sources" about a route that is not
    // filtered; it says only what differs from the default.
    function test_annotation_data() {
        return [
            { tag: "default",       min: -1, max: -1, offset: 0,  expected: "" },
            { tag: "offset-only",   min: -1, max: -1, offset: 2,  expected: "+2" },
            { tag: "range-only",    min: 1,  max: 8,  offset: 0,  expected: "1 to 8" },
            { tag: "both",          min: 1,  max: 8,  offset: 16, expected: "1 to 8  +16" },
            { tag: "open-ended",    min: 17, max: -1, offset: 0,  expected: "17 and up" }
        ];
    }
    function test_annotation(row) {
        compare(Format.annotation(row.min, row.max, row.offset), row.expected);
    }

    function test_scale_data() {
        return [
            { tag: "identity", x: 1,    y: 1,   z: 1,   expected: "no scaling" },
            { tag: "mirror",   x: -1,   y: 1,   z: 1,   expected: "-1, 1, 1" },
            { tag: "half",     x: 0.5,  y: 0.5, z: 0.5, expected: "0.5, 0.5, 0.5" },
            { tag: "mixed",    x: -2,   y: 1,   z: 0.25, expected: "-2, 1, 0.25" }
        ];
    }
    function test_scale(row) {
        compare(Format.scale(row.x, row.y, row.z), row.expected);
    }

    // A round number must not lose its zeros to the trailing-zero strip.
    function test_number_keeps_round_values_data() {
        return [
            { tag: "one",      value: 1,     expected: "1" },
            { tag: "ten",      value: 10,    expected: "10" },
            { tag: "hundred",  value: 100,   expected: "100" },
            { tag: "fraction", value: 0.125, expected: "0.125" },
            { tag: "negative", value: -1.5,  expected: "-1.5" }
        ];
    }
    function test_number_keeps_round_values(row) {
        compare(Format.number(row.value), row.expected);
    }

    // Plain text only: no dashes, arrows or other symbols to render.
    function test_output_is_plain_ascii() {
        var samples = [
            Format.range(-1, -1), Format.range(1, 8), Format.range(17, -1),
            Format.route(1, 8, 16), Format.annotation(-1, -1, 2),
            Format.scale(1, 1, 1), Format.scale(-1, 0.5, 2)
        ];
        for (var i = 0; i < samples.length; i++) {
            for (var j = 0; j < samples[i].length; j++) {
                verify(samples[i].charCodeAt(j) < 128,
                       "non-ascii in " + JSON.stringify(samples[i]));
            }
        }
    }
}
