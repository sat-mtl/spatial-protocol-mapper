.pragma library

// The script "+ New script" starts from. __ID__ and __NAME__ are filled in
// with a free id and name. It lives in a template literal, so it must not
// contain backticks or dollar-brace sequences (tst_handlers checks it compiles).

var source = `// __NAME__: a starting point for your own protocol handler.
//
// As written, it speaks <root>/<n>/xyz with x y z floats, in both directions.
// Edit it, press Apply (Ctrl+S), then pick "__NAME__" as an input's or
// output's protocol; the "..." button next to the protocol edits the settings
// declared in params below.
//
// See docs/HANDLERS.md for the full API. In short:
//   - module.exports is the handler descriptor;
//   - spm holds the constants and helpers;
//   - nothing on the per-message path should allocate: build buffers and
//     address templates up front and reuse them.

module.exports = {
    apiVersion: 1,
    id: "__ID__",          // unique; devices remember their protocol by it
    name: "__NAME__",
    defaultPort: 9100,

    // No "matches": the address depends on a setting, so this handler is not
    // offered to "Auto" inputs. A fixed prefix ("/source/") would be.

    params: [
        { key: "root", label: "Address root", type: "string", default: "/obj" },
        { key: "range", label: "Field half-width", type: "real", default: 1.0, min: 0.001 },
        { key: "zeroBased", label: "Zero-based indices", type: "bool", default: false }
    ],

    createInput: function (ctx) {
        const p = ctx.params;
        const shift = p.zeroBased ? 1 : 0;
        const k = spm.MBAP_EXTENDED_RADIUS / p.range;

        // The table's keys are address patterns; {n} is the source index.
        // Settings changes rebuild the instance (no onParamsChanged here), so
        // the pattern can depend on them.
        const table = {};
        table[p.root + "/{n}/xyz"] = function (n, args, ev) {
            if (!args || args.length < 3) return false;
            ev.type = spm.POSITION;
            ev.source = n + shift;
            ev.coords = spm.CARTESIAN;
            ev.x = args[0] * k;
            ev.y = args[1] * k;
            ev.z = args[2] * k;
            return true;     // route it; false drops the message
        };
        return table;
    },

    createOutput: function (ctx) {
        const p = ctx.params;
        let address, k, shift;
        const xyz = [0, 0, 0];
        const cart = { x: 0, y: 0, z: 0 };

        // Live settings: the instance stays, only what depends on them changes.
        function configure() {
            address = spm.addressTemplate(p.root + "/{n}/xyz");
            k = p.range / spm.MBAP_EXTENDED_RADIUS;
            shift = p.zeroBased ? 1 : 0;
        }
        configure();

        return {
            onParamsChanged: configure,

            position: function (ev) {
                // Whatever family the sender used, this protocol wants cartesian.
                spm.toCartesian(ev, cart);
                xyz[0] = spm.clamp(cart.x * k, -p.range, p.range);
                xyz[1] = spm.clamp(cart.y * k, -p.range, p.range);
                xyz[2] = spm.clamp(cart.z * k, -p.range, p.range);
                ctx.send(address(ev.source - shift), xyz);
            },

            clear: function (ev) {
                xyz[0] = 0; xyz[1] = 0; xyz[2] = 0;
                ctx.send(address(ev.source - shift), xyz);
            }
            // No algorithm() or native(): those events are skipped for this output.
        };
    }
};
`;

function make(id, name) {
    return source.split("__ID__").join(id).split("__NAME__").join(name);
}
