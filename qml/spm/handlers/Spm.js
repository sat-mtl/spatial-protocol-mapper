.pragma library

// The `spm` object every protocol handler sees: event constants, coordinate
// helpers and the per-input scaling the engine applies before routing.
//
// The event
// ---------
// One fixed-shape object per input device, allocated once and overwritten by
// every message. Handlers fill it and must not keep a reference to it.
//
//   type       POSITION | CLEAR | ALGORITHM | NATIVE
//   source     1-based source index, or -1 when the message has none
//   offset     the route's source offset, already added to `source` (encoders)
//   coords     SPHERICAL | CARTESIAN: the family the sender wrote
//   radians    the sender wrote its angles in radians (a hint for encoders
//              that can re-emit them that way; the fields are always degrees)
//   azimuth, elevation   degrees, SpatGRIS convention: -90 = left, +90 = up
//   distance   1 = the speaker sphere
//   x, y, z    SpatGRIS units: x right, y front, z up, +-MBAP_EXTENDED_RADIUS
//   hspan, vspan         extents, 0..1
//   value      ALGORITHM payload ("dome" | "cube")
//   nativeProtocol, nativeAddress, nativeArgs
//              the message as received, for encoders of that same protocol.
//              Cleared by the engine whenever it alters the event (scaling).

var POSITION = 1;
var CLEAR = 2;
var ALGORITHM = 3;
var NATIVE = 4;

var SPHERICAL = 1;
var CARTESIAN = 2;

var API_VERSION = 1;

// SpatGRIS MBAP_EXTENDED_RADIUS (sg_constants.hpp:71) -- the cartesian clamp
// applied by CartesianVector::clampedToFarField (sg_CartesianVector.hpp:182-187).
var MBAP_EXTENDED_RADIUS = 1.6666667;

var DEG = 180.0 / Math.PI;
var RAD = Math.PI / 180.0;

function newEvent() {
    return {
        type: 0, source: -1, offset: 0,
        coords: SPHERICAL, radians: false,
        azimuth: 0, elevation: 0, distance: 1,
        x: 0, y: 0, z: 0,
        hspan: 0, vspan: 0,
        value: null,
        nativeProtocol: null, nativeAddress: null, nativeArgs: null
    };
}

function clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

// SpatGRIS convention: azimuth is measured from the front (+y) toward the
// right (+x), elevation from the horizon toward +z. Both write into `out`
// ({x, y, z} / {azimuth, elevation, distance}) so the caller owns the memory.
function sphericalToCartesian(azDeg, elDeg, r, out) {
    const az = azDeg * RAD, el = elDeg * RAD;
    const ce = Math.cos(el);
    out.x = r * ce * Math.sin(az);
    out.y = r * ce * Math.cos(az);
    out.z = r * Math.sin(el);
    return out;
}

function cartesianToSpherical(x, y, z, out) {
    const r = Math.sqrt(x * x + y * y + z * z);
    // At the origin there is no direction to report; asin(0/0) would be NaN.
    if (r < 1e-12) {
        out.azimuth = 0; out.elevation = 0; out.distance = 0;
        return out;
    }
    out.azimuth = Math.atan2(x, y) * DEG;
    out.elevation = Math.asin(z / r) * DEG;
    out.distance = r;
    return out;
}

// The event in the other family, without touching it.
function toCartesian(ev, out) {
    if (ev.coords === CARTESIAN) {
        out.x = ev.x; out.y = ev.y; out.z = ev.z;
        return out;
    }
    return sphericalToCartesian(ev.azimuth, ev.elevation, ev.distance, out);
}

function toSpherical(ev, out) {
    if (ev.coords === SPHERICAL) {
        out.azimuth = ev.azimuth; out.elevation = ev.elevation; out.distance = ev.distance;
        return out;
    }
    return cartesianToSpherical(ev.x, ev.y, ev.z, out);
}

// ----- Per-input scaling ------------------------------------------------- //
// A negative factor mirrors that axis. Spherical positions are scaled through
// cartesian and back, so they stay in the family the sender chose.
var g_scratch = { x: 0, y: 0, z: 0, azimuth: 0, elevation: 0, distance: 0 };

function isIdentityScale(sx, sy, sz) {
    return sx === 1 && sy === 1 && sz === 1;
}

// In place. Returns false when nothing was changed.
function scaleEvent(ev, sx, sy, sz) {
    if (ev.type !== POSITION || isIdentityScale(sx, sy, sz))
        return false;

    if (ev.coords === CARTESIAN) {
        ev.x *= sx; ev.y *= sy; ev.z *= sz;
    } else {
        const p = sphericalToCartesian(ev.azimuth, ev.elevation, ev.distance, g_scratch);
        const q = cartesianToSpherical(p.x * sx, p.y * sy, p.z * sz, g_scratch);
        ev.azimuth = q.azimuth; ev.elevation = q.elevation; ev.distance = q.distance;
    }
    // The verbatim form now describes a position the source is no longer at.
    ev.nativeProtocol = null;
    ev.nativeAddress = null;
    ev.nativeArgs = null;
    return true;
}

// ----- Address templates ------------------------------------------------- //
// "/adm/obj/{n}/aed" -> a function n => "/adm/obj/7/aed" that builds each
// string once and then hands back the cached one.
function addressTemplate(pattern) {
    const at = pattern.indexOf("{n}");
    if (at < 0)
        return function () { return pattern; };
    const head = pattern.substring(0, at);
    const tail = pattern.substring(at + 3);
    const cache = [];
    return function (n) {
        if (n >= 0 && n < 65536 && (n | 0) === n) {
            let s = cache[n];
            if (s === undefined) {
                s = head + n + tail;
                cache[n] = s;
            }
            return s;
        }
        return head + n + tail;
    };
}

// ----- Address patterns -------------------------------------------------- //
// Input handlers key their functions by pattern: literal segments plus at most
// one "{n}" segment, a decimal source index. Compiled once per pattern, then
// matched by scanning characters: no regex, no split, no allocation.
function compilePattern(pattern) {
    const at = pattern.indexOf("{n}");
    if (at < 0)
        return { pattern: pattern, head: pattern, tail: null };
    return { pattern: pattern, head: pattern.substring(0, at), tail: pattern.substring(at + 3) };
}

// The source index the address carries for this pattern, -1 when the pattern
// has none, or -2 when the address does not match.
function matchPattern(p, address) {
    if (p.tail === null)
        return address === p.head ? -1 : -2;

    const headLen = p.head.length;
    const tailLen = p.tail.length;
    if (address.length <= headLen + tailLen) return -2;
    if (!address.startsWith(p.head)) return -2;
    if (!address.endsWith(p.tail)) return -2;

    const end = address.length - tailLen;
    let n = 0;
    for (let i = headLen; i < end; i++) {
        const c = address.charCodeAt(i) - 48;
        if (c < 0 || c > 9) return -2;
        n = n * 10 + c;
    }
    return n;
}

// The leading run of digits in `address` from `start`, or -1.
function indexAt(address, start) {
    let n = 0, i = start;
    for (; i < address.length; i++) {
        const c = address.charCodeAt(i) - 48;
        if (c < 0 || c > 9) break;
        n = n * 10 + c;
    }
    return i === start ? -1 : n;
}

// What handlers get as `spm`. Frozen so one script cannot break another.
var api = Object.freeze({
    POSITION: POSITION, CLEAR: CLEAR, ALGORITHM: ALGORITHM, NATIVE: NATIVE,
    SPHERICAL: SPHERICAL, CARTESIAN: CARTESIAN,
    API_VERSION: API_VERSION,
    MBAP_EXTENDED_RADIUS: MBAP_EXTENDED_RADIUS,
    DEG: DEG, RAD: RAD,
    clamp: clamp,
    sphericalToCartesian: sphericalToCartesian,
    cartesianToSpherical: cartesianToSpherical,
    toCartesian: toCartesian,
    toSpherical: toSpherical,
    addressTemplate: addressTemplate,
    indexAt: indexAt
});
