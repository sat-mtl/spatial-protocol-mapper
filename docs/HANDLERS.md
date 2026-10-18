# Protocol handlers

Every protocol the mapper speaks is a *handler*: a small JavaScript object that
turns incoming OSC into **events**, and events into outgoing OSC. SpatGRIS,
ADM-OSC and SPAT Revolution are bundled handlers
(`qml/spm/handlers/`); your own load from the **SCRIPTS** tab and are written
the same way.

A handler can have an input side, an output side, or both. Routing (which
input feeds which output, source ranges, offsets) and per-input scaling stay
in the engine; a handler only translates.

```
 OSC in ──► input handler ──► event ──► scale ──► route filter + offset ──► output handler ──► OSC out
```

The quickest start is **SCRIPTS → + New script**: it opens a complete,
commented handler in the built-in editor
([`qml/spm/handlers/Template.js`](../qml/spm/handlers/Template.js)), ready to
apply and adapt.

## The file

A handler script assigns `module.exports`:

```js
module.exports = {
    apiVersion: 1,                // required
    id: "my-protocol",            // required, unique; saved with each device
    name: "My protocol",          // shown in the pickers (defaults to id)
    defaultPort: 9000,            // for new outputs
    matches: "/my/",              // address prefix; makes the input side available to "Auto"
    params: [ /* per-device settings, see below */ ],

    createInput: function (ctx) { /* returns an address table */ },
    createOutput: function (ctx) { /* returns an encoder */ },

    // Optional: claim an address space for verbatim passthrough (see below).
    native: { prefix: "/my/", source: function (address) { return -1; } }
};
```

Scripts run in strict mode. `spm` is in scope; `Qt`, `XMLHttpRequest` and
`Protocols` are not: handlers never touch the app, its sockets or QML. That
keeps a broken script from reaching into the rest of the app, but **it is not
a sandbox**: only load scripts you trust.

## Events

Each input owns one event object. It is reset and refilled for every message.
**Do not keep a reference to it** beyond the call that received it.

| Field | Meaning |
|---|---|
| `type` | `spm.POSITION`, `spm.CLEAR`, `spm.ALGORITHM` or `spm.NATIVE` |
| `source` | 1-based source index, `-1` when the message has none. Output side: the route offset is already added |
| `offset` | Output side: the route offset that was added |
| `coords` | `spm.SPHERICAL` or `spm.CARTESIAN`: the family the sender wrote |
| `azimuth`, `elevation` | Degrees, SpatGRIS convention: −90 = left, +90 = up |
| `distance` | 1 = the speaker sphere |
| `x`, `y`, `z` | SpatGRIS units: x right, y front, z up, ±`spm.MBAP_EXTENDED_RADIUS` (1.6667) |
| `hspan`, `vspan` | Extents, 0..1 |
| `radians` | Hint: the sender used radians. Fields stay in degrees |
| `value` | `ALGORITHM` payload: `"dome"` or `"cube"` |
| `nativeProtocol`, `nativeAddress`, `nativeArgs` | The message as received, for encoders of the same protocol to re-emit verbatim. Cleared when the engine changes the event (scaling) |

Only the fields of the event's `coords` family are meaningful. Use
`spm.toCartesian(ev, out)` or `spm.toSpherical(ev, out)` to get the other one.

## Input side

`createInput(ctx)` runs once per input device and returns a table of
functions keyed by **address pattern**:

```js
createInput: function (ctx) {
    const sources = [];                      // per-device state lives here
    return {
        "/my/{n}/pos": function (n, args, ev, address) {
            if (!args || args.length < 3) return false;
            ev.type = spm.POSITION;
            ev.source = n;
            ev.coords = spm.CARTESIAN;
            ev.x = args[0]; ev.y = args[1]; ev.z = args[2];
            return true;                     // route the event
        },
        "*": function (n, args, ev, address) {
            // anything else under `matches` (n is -1)
            return false;                    // nothing to route
        }
    };
}
```

- A pattern is literal except for at most one `{n}`, a decimal source index.
  It is compiled once. Each distinct address is resolved once and then cached
  per input, so a function costs one map lookup per message.
- With a declared protocol, the input takes addresses under `matches` (or every
  address, when `matches` is absent). With "Auto", each address goes to the
  first handler whose `matches` prefix it starts with: the bundled handlers
  first, then scripts in loading order.
- Return `true` to route `ev`. Call `ctx.emit()` to route it immediately,
  for instance to produce several events from one message, then return `false`.
- Inputs are decoded even when nothing is routed, so accumulated state stays
  current.

## Output side

`createOutput(ctx)` runs once per output device and returns an **encoder**.
It has one method per event type it handles; missing methods mean "skip".

```js
createOutput: function (ctx) {
    const pos = spm.addressTemplate("/my/{n}/pos");   // n => cached string
    const buf = [0, 0, 0];                              // reused for every send
    const cart = { x: 0, y: 0, z: 0 };
    return {
        position: function (ev) {
            spm.toCartesian(ev, cart);
            buf[0] = cart.x; buf[1] = cart.y; buf[2] = cart.z;
            ctx.send(pos(ev.source), buf);
        },
        clear: function (ev) { /* … */ },
        algorithm: function (ev) { /* … */ },
        native: function (ev) {
            if (ev.nativeProtocol === "my-protocol") ctx.send(ev.nativeAddress, ev.nativeArgs);
        },
        onParamsChanged: function () { /* optional, see params */ },
        destroy: function () { /* optional */ }
    };
}
```

`ctx.send(address, args)` sends one OSC message. The arguments are serialized
before it returns, so **reusing the same array for every send is safe**, and is
the intended pattern.

## Verbatim passthrough (`native`)

Some messages have no place in the event model: ADM gain, mute, `/adm/lis`,
and so on. A handler can claim an address space:

```js
native: { prefix: "/adm/", source: function (address) { /* index or -1 */ } }
```

When no decoder produced an event for an address under that prefix, on any
input, the engine sends an `spm.NATIVE` event with `nativeProtocol` set to the
claiming handler's id. Only that protocol's encoders forward it, through their
`native()` method. `source()` gives the source index used by the route filter,
or `-1` to bypass it.

## `ctx`

| Member | Side | |
|---|---|---|
| `ctx.params` | both | The device's settings. Updated in place on change |
| `ctx.device` | both | `{ id, name }` |
| `ctx.send(address, args)` | output | Send one message |
| `ctx.emit()` | input | Route the current event now |
| `ctx.log(msg)` | both | Console line, prefixed with handler and device |
| `ctx.error(msg)` | both | Show a problem on the device's row |

## Params

Per-device settings, edited with the **…** button next to a device's protocol
and saved with the configuration:

```js
params: [
    { key: "root",  label: "Address root", type: "string", default: "/obj" },
    { key: "range", label: "Half-width",   type: "real",   default: 1, min: 0.001 },
    { key: "count", type: "int", default: 8, min: 1, max: 64 },
    { key: "flip",  type: "bool", default: false },
    { key: "mode",  type: "enum", options: ["xyz", "aed"] }
]
```

Values are coerced to the declared type and clamped to `min`/`max`. When they
change, an instance that defines `onParamsChanged()` is kept and sees the new
values in `ctx.params`. Otherwise it is rebuilt, which also resets any
accumulated state.

## `spm`

Constants: `POSITION`, `CLEAR`, `ALGORITHM`, `NATIVE`, `SPHERICAL`,
`CARTESIAN`, `API_VERSION`, `MBAP_EXTENDED_RADIUS`, `DEG` (radians → degrees
factor), `RAD` (degrees → radians).

Helpers, all writing into an object you pass in, so nothing allocates:

- `toCartesian(ev, out)`, `toSpherical(ev, out)`
- `sphericalToCartesian(az, el, r, out)`, `cartesianToSpherical(x, y, z, out)`
- `addressTemplate("/a/{n}/b")` returns `n => string`, cached per index
- `indexAt(address, start)`: the decimal number at `start`, or −1
- `clamp(v, lo, hi)`

## Performance rules

Messages are handled on the GUI thread, and garbage collection pauses there
too. In the per-message functions:

- Don't allocate: no `[]`, `{}`, template strings, regexes, closures,
  `concat`/`slice` or destructuring. Allocate in `createInput`/`createOutput`.
- Keep object shapes fixed: add every property of a state object when you
  create it.
- Use `spm.addressTemplate` for outgoing addresses and reuse send buffers.

`tests/tst_handlers.qml` has benchmarks (`benchmark_*`) to measure against.

## Failures

A handler that throws loses that one message. The other routes still get it,
the device's row shows the error, and the console logs the first throw and
every thousandth after that. A device whose protocol is not loaded (a missing
or broken script) keeps its protocol, settings and routes, and resumes once
the script loads.

## Writing and loading scripts

The **SCRIPTS** tab lists every handler.

- **+ New script** starts a script from the template. It is stored in the
  app's settings, not in a file, so it also works where there is no file
  access (the web build).
- **+ Open file** adds a `.js` file. It is saved by path and read again at
  startup; **Reload** picks up changes made in another editor.
- **Edit** opens either kind in the built-in editor. **Apply** (Ctrl+S) saves
  the script (to the settings, or back to its file) and loads it. Devices on
  its protocol get a fresh instance.

The editor shows line numbers. Tab and Enter keep the indentation. When a
script does not compile, or throws while loading, the failing line is
highlighted. The edit is saved anyway, so nothing is lost, but it is not
applied: the version that was running keeps running.

Reading and writing files from QML needs `QML_XHR_ALLOW_FILE_READ=1` and
`QML_XHR_ALLOW_FILE_WRITE=1`, which the app's `environment` sets. Without them,
opening or saving a file reports an error after a couple of seconds.
