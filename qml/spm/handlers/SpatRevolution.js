.pragma library
.import "Spm.js" as Spm

// SPAT Revolution: /source/{n}/aed, /source/{n}/xyz, /source/{n}/spread.
//
// Azimuth keeps the SpatGRIS sign, radius is a percentage, and spread is one
// figure (a percentage) standing for both extents.
var spm = Spm.api;
var module = { exports: null };

module.exports = {
    apiVersion: 1,
    id: "SPAT Revolution",
    name: "SPAT Revolution",
    defaultPort: 8088,
    matches: "/source/",

    // One parameter per message, so the accumulator lives on the input.
    createInput: function (ctx) {
        const sources = [];

        function get(n) {
            let s = sources[n];
            if (s === undefined) {
                s = { azim: 0, elev: 0, dist: 1.0, x: 0, y: 0, z: 0, spread: 0, polar: false };
                sources[n] = s;
            }
            return s;
        }

        function emit(n, s, ev) {
            ev.type = spm.POSITION;
            ev.source = n;
            ev.hspan = s.spread;
            ev.vspan = s.spread;
            if (s.polar) {
                ev.coords = spm.SPHERICAL;
                ev.radians = false;
                ev.azimuth = s.azim;
                ev.elevation = s.elev;
                ev.distance = s.dist;
            } else {
                ev.coords = spm.CARTESIAN;
                ev.x = s.x; ev.y = s.y; ev.z = s.z;
            }
            return true;
        }

        // mode/gain/mute and the rest have no equivalent in the event model.
        return {
            "/source/{n}/aed": function (n, a, ev) {
                if (!a || a.length < 3) return false;
                const s = get(n);
                s.azim = a[0]; s.elev = a[1]; s.dist = a[2] / 100.0; s.polar = true;
                return emit(n, s, ev);
            },
            "/source/{n}/xyz": function (n, a, ev) {
                if (!a || a.length < 3) return false;
                const s = get(n);
                s.x = a[0]; s.y = a[1]; s.z = a[2]; s.polar = false;
                return emit(n, s, ev);
            },
            // Spread alone doesn't switch coordinate mode.
            "/source/{n}/spread": function (n, a, ev) {
                if (!a || a.length < 1) return false;
                const s = get(n);
                s.spread = a[0] / 100.0;
                return emit(n, s, ev);
            }
        };
    },

    // Unlike ADM, SPAT cartesian is not rescaled.
    createOutput: function (ctx) {
        const aed = spm.addressTemplate("/source/{n}/aed");
        const xyz = spm.addressTemplate("/source/{n}/xyz");
        const spread = spm.addressTemplate("/source/{n}/spread");
        const mode = spm.addressTemplate("/source/{n}/mode");
        const b3 = [0, 0, 0];
        const b1 = [0];
        const m1 = [""];
        const zero = [0, 0, 0];

        return {
            position: function (ev) {
                const n = ev.source;
                if (ev.coords === spm.CARTESIAN) {
                    b3[0] = ev.x; b3[1] = ev.y; b3[2] = ev.z;
                    ctx.send(xyz(n), b3);
                } else {
                    b3[0] = ev.azimuth; b3[1] = ev.elevation; b3[2] = ev.distance * 100;
                    ctx.send(aed(n), b3);
                }
                b1[0] = (ev.hspan + ev.vspan) / 2 * 100;
                ctx.send(spread(n), b1);
            },
            clear: function (ev) {
                ctx.send(xyz(ev.source), zero);
            },
            algorithm: function (ev) {
                if (ev.value === null || ev.value === undefined) return;
                m1[0] = ev.value === "dome" ? "dome" : "panning";
                ctx.send(mode(ev.source), m1);
            }
        };
    }
};
