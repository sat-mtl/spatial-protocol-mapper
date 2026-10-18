.pragma library
.import "Spm.js" as Spm

// SpatGRIS: /spat/serv, in both directions.
//
// Bundled handlers are written exactly like user scripts; only these two
// lines differ, because a user script receives `module` and `spm` as
// parameters instead.
var spm = Spm.api;
var module = { exports: null };

module.exports = {
    apiVersion: 1,
    id: "SpatGRIS",
    name: "SpatGRIS",
    defaultPort: 18042,
    matches: "/spat/serv",

    createInput: function (ctx) {
        const HALF_PI = Math.PI / 2.;

        function decode(n, a, ev, address) {
            if (!a || a.length < 2) return false;

            if (typeof a[0] === "number") {
                // Legacy format: [sourceIndex, az, el, hspan, vspan, radius, reserved]
                // 0-based index, polar in radians, elevation from the zenith.
                if (a.length < 7) return false;
                ev.type = spm.POSITION;
                ev.source = 1 + a[0];
                ev.coords = spm.SPHERICAL;
                ev.radians = true;
                ev.azimuth = a[1] * spm.DEG;
                ev.elevation = (HALF_PI - a[2]) * spm.DEG;
                ev.distance = a[5];
                ev.hspan = a[3] / 2.;
                ev.vspan = a[4] * 2.;
                // SpatGRIS routes the legacy form through a *cylindrical*
                // LegacyLbapPosition::toPosition() in Cube/MBAP mode, but "pol"
                // through a *spherical* conversion: rewriting legacy to "pol"
                // moves the source (az=0, colat=pi/4, dist=1 lands at
                // (0,0.707,0.707) instead of (0,1,0.5)). A SpatGRIS output
                // re-emits this payload unchanged; every other output uses the
                // normalized position above, which is correct for them.
                ev.nativeProtocol = "SpatGRIS";
                ev.nativeAddress = address;
                ev.nativeArgs = a;
                return true;
            }

            const idx = (typeof a[1] === "number") ? a[1] : -1;
            switch (a[0]) {
            case "pol":
            case "deg":
                if (a.length < 7) return false;
                ev.type = spm.POSITION;
                ev.source = idx;
                ev.coords = spm.SPHERICAL;
                ev.radians = (a[0] === "pol");
                ev.azimuth = ev.radians ? a[2] * spm.DEG : a[2];
                ev.elevation = ev.radians ? a[3] * spm.DEG : a[3];
                ev.distance = a[4];
                ev.hspan = a[5];
                ev.vspan = a[6];
                return true;
            case "car":
                if (a.length < 7) return false;
                ev.type = spm.POSITION;
                ev.source = idx;
                ev.coords = spm.CARTESIAN;
                ev.x = a[2]; ev.y = a[3]; ev.z = a[4];
                ev.hspan = a[5];
                ev.vspan = a[6];
                return true;
            case "clr":
                ev.type = spm.CLEAR;
                ev.source = idx;
                return true;
            case "alg":
                ev.type = spm.ALGORITHM;
                ev.source = idx;
                ev.value = a.length > 2 ? a[2] : null;
                return true;
            }
            // Commands we do not model (e.g. "reset <id>", sg_OscInput.cpp:186-193)
            // still reach SpatGRIS outputs.
            ev.type = spm.NATIVE;
            ev.source = idx;
            ev.nativeProtocol = "SpatGRIS";
            ev.nativeAddress = address;
            ev.nativeArgs = a;
            return true;
        }

        // Everything under the prefix, including the bare address.
        return { "*": decode };
    },

    // The SpatGRIS server speaks /spat/serv natively, so the command goes out
    // in the coordinate system it arrived in. No polar<->cartesian round trip.
    createOutput: function (ctx) {
        const ADDR = "/spat/serv";
        const pos = ["", 0, 0, 0, 0, 0, 0];
        const legacy = [];
        const clr = ["clr", 0];
        const alg = ["alg", 0, ""];
        const nat = [];

        return {
            position: function (ev) {
                // A legacy-form input goes back out in the legacy form, untouched.
                // `source` is 1-based (+ any route offset); the wire form is 0-based.
                if (ev.nativeProtocol === "SpatGRIS" && typeof ev.nativeArgs[0] === "number") {
                    const a = ev.nativeArgs;
                    legacy.length = a.length;
                    legacy[0] = ev.source - 1;
                    for (let i = 1; i < a.length; i++) legacy[i] = a[i];
                    ctx.send(ADDR, legacy);
                    return;
                }
                pos[1] = ev.source;
                if (ev.coords === spm.CARTESIAN) {
                    pos[0] = "car";
                    pos[2] = ev.x; pos[3] = ev.y; pos[4] = ev.z;
                } else if (ev.radians) {
                    pos[0] = "pol";
                    pos[2] = ev.azimuth * spm.RAD; pos[3] = ev.elevation * spm.RAD; pos[4] = ev.distance;
                } else {
                    pos[0] = "deg";
                    pos[2] = ev.azimuth; pos[3] = ev.elevation; pos[4] = ev.distance;
                }
                pos[5] = ev.hspan;
                pos[6] = ev.vspan;
                ctx.send(ADDR, pos);
            },
            clear: function (ev) {
                clr[1] = ev.source;
                ctx.send(ADDR, clr);
            },
            algorithm: function (ev) {
                if (ev.value === null || ev.value === undefined) return;
                alg[1] = ev.source;
                alg[2] = ev.value;
                ctx.send(ADDR, alg);
            },
            native: function (ev) {
                if (ev.nativeProtocol !== "SpatGRIS") return;
                const a = ev.nativeArgs;
                if (typeof a[0] !== "string" || a[0].length === 0) return;
                // [command, index, ...rest], with the route's index.
                nat.length = Math.max(2, a.length);
                nat[0] = a[0];
                nat[1] = ev.source;
                for (let i = 2; i < a.length; i++) nat[i] = a[i];
                ctx.send(ADDR, nat);
            }
        };
    }
};
