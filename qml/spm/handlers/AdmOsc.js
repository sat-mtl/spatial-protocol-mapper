.pragma library
.import "Spm.js" as Spm

// ADM-OSC (v1.0): /adm/obj/{n}/…, in both directions.
var spm = Spm.api;
var module = { exports: null };

// "/adm/obj/" is 9 characters.
var OBJ = "/adm/obj/";

// /adm/obj/{n}/… carries a source index; /adm/lis and /adm/env do not.
// Returns the index and where the "/…" after it starts, or -1.
function objIndexEnd(address) {
    if (!address.startsWith(OBJ)) return -1;
    let i = OBJ.length;
    while (i < address.length) {
        const c = address.charCodeAt(i);
        if (c < 48 || c > 57) break;
        i++;
    }
    if (i === OBJ.length || i >= address.length || address.charCodeAt(i) !== 47 /* / */)
        return -1;
    return i;
}

module.exports = {
    apiVersion: 1,
    id: "ADM-OSC",
    name: "ADM-OSC",
    defaultPort: 9000,
    matches: OBJ,

    // ADM-specific features (gain, mute, name, /adm/lis, /adm/env, …) have no
    // place in the event model. Whatever no decoder turned into an event, on
    // any input, still reaches ADM-OSC outputs verbatim.
    native: {
        prefix: "/adm/",
        source: function (address) {
            const end = objIndexEnd(address);
            return end < 0 ? -1 : spm.indexAt(address, OBJ.length);
        }
    },

    // ADM sends per-parameter messages, not atomic packets, so each input keeps
    // per-source state and emits a complete position on every update. The last
    // coordinate family written decides spherical or cartesian downstream.
    createInput: function (ctx) {
        const sources = [];

        function get(n) {
            let s = sources[n];
            if (s === undefined) {
                // Defaults per ADM-OSC spec: azim, elev 0; dist 1 (on the
                // reference sphere); xyz 0; w 0.
                s = { azim: 0, elev: 0, dist: 1.0, x: 0, y: 0, z: 0, w: 0, polar: false };
                sources[n] = s;
            }
            return s;
        }

        // ADM azimuth is +90 = left, SpatGRIS -90 = left: the sign flips.
        // Cartesian axes match (x = L/R, y = B/F, z = D/U), so xyz passes
        // through. ADM has no vertical extent, so vspan is 0.
        function emit(n, s, ev) {
            ev.type = spm.POSITION;
            ev.source = n;
            ev.hspan = s.w;
            ev.vspan = 0;
            if (s.polar) {
                ev.coords = spm.SPHERICAL;
                ev.radians = false;
                ev.azimuth = -s.azim;
                ev.elevation = s.elev;
                ev.distance = s.dist;
            } else {
                ev.coords = spm.CARTESIAN;
                ev.x = s.x; ev.y = s.y; ev.z = s.z;
            }
            return true;
        }

        // A short payload returns false; the message is then forwarded verbatim.
        return {
            "/adm/obj/{n}/aed": function (n, a, ev) {
                if (!a || a.length < 3) return false;
                const s = get(n);
                s.azim = a[0]; s.elev = a[1]; s.dist = a[2]; s.polar = true;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/azim": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.azim = a[0]; s.polar = true;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/elev": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.elev = a[0]; s.polar = true;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/dist": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.dist = a[0]; s.polar = true;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/xyz": function (n, a, ev) {
                if (!a || a.length < 3) return false;
                const s = get(n);
                s.x = a[0]; s.y = a[1]; s.z = a[2]; s.polar = false;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/xy": function (n, a, ev) {
                if (!a || a.length < 2) return false;
                const s = get(n);
                s.x = a[0]; s.y = a[1]; s.polar = false;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/x": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.x = a[0]; s.polar = false;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/y": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.y = a[0]; s.polar = false;
                return emit(n, s, ev);
            },
            "/adm/obj/{n}/z": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.z = a[0]; s.polar = false;
                return emit(n, s, ev);
            },
            // Width alone doesn't switch coordinate mode.
            "/adm/obj/{n}/w": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.w = a[0];
                return emit(n, s, ev);
            }
        };
    },

    // Out:
    //   - Azimuth flips sign (SpatGRIS -90 = left, ADM +90 = left); elevation
    //     does not.
    //   - Ranges differ: SpatGRIS cartesian is the MBAP extended field
    //     (+-MBAP_EXTENDED_RADIUS) while ADM-OSC is normalized +-1. Letting the
    //     receiver clamp (ADM-OSC §9) is NOT position-preserving: every source
    //     beyond 60% of full scale would collapse onto the wall. The axes are
    //     scaled instead. Polar radius is a distance, not a bounded axis, and is
    //     left alone.
    //   - ADM has no vertical extent; vspan is dropped. ADM /w is normalized
    //     [0, 1], as is hspan.
    //   - Packed /aed and /xyz, per the spec's atomicity recommendation.
    createOutput: function (ctx) {
        const aed = spm.addressTemplate("/adm/obj/{n}/aed");
        const xyz = spm.addressTemplate("/adm/obj/{n}/xyz");
        const w = spm.addressTemplate("/adm/obj/{n}/w");
        const b3 = [0, 0, 0];
        const b1 = [0];
        const zero = [0, 0, 0];
        const k = 1 / spm.MBAP_EXTENDED_RADIUS;
        // offset -> (address -> address with the offset index)
        const rewritten = new Map();

        function shifted(address, offset) {
            let m = rewritten.get(offset);
            if (m === undefined) { m = new Map(); rewritten.set(offset, m); }
            let s = m.get(address);
            if (s === undefined) {
                const end = objIndexEnd(address);
                s = OBJ + (spm.indexAt(address, OBJ.length) + offset) + address.substring(end);
                if (m.size > 4096) m.clear();
                m.set(address, s);
            }
            return s;
        }

        return {
            position: function (ev) {
                const n = ev.source;
                if (ev.coords === spm.CARTESIAN) {
                    b3[0] = ev.x * k; b3[1] = ev.y * k; b3[2] = ev.z * k;
                    ctx.send(xyz(n), b3);
                } else {
                    b3[0] = -ev.azimuth; b3[1] = ev.elevation; b3[2] = ev.distance;
                    ctx.send(aed(n), b3);
                }
                b1[0] = ev.hspan;
                ctx.send(w(n), b1);
            },
            clear: function (ev) {
                ctx.send(xyz(ev.source), zero);
            },
            // ADM has no algorithm concept: no algorithm() method.
            native: function (ev) {
                if (ev.nativeProtocol !== "ADM-OSC") return;
                const inSource = ev.source - ev.offset;
                const address = (ev.offset !== 0 && inSource >= 0)
                        ? shifted(ev.nativeAddress, ev.offset)
                        : ev.nativeAddress;
                ctx.send(address, ev.nativeArgs);
            }
        };
    }
};
