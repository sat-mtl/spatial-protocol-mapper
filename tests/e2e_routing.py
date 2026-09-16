#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# © Société des arts technologiques
"""
End-to-end routing test: drives the real app over UDP.

tst_engine.qml covers the conversion table and the route predicates as pure
functions. This covers what it cannot reach — the input sockets, the OSC
parser, per-output sockets, the dispatch index, and the settings migration —
by seeding a known configuration, launching the app, sending OSC at a listen
port and asserting on what comes out the other side.

Not part of CI: it needs a built ossia-score (see ./test.sh). Run it locally
before and after touching the routing engine.

    python3 tests/e2e_routing.py

Exits non-zero on the first failed expectation.
"""

import json
import os
import re
import socket
import struct
import subprocess
import sys
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONF = os.path.expanduser("~/.config/ossia/score.conf")

PORT_A = 18032          # first input
PORT_B = 18033          # second input, for the isolation checks
SINK_SPATGRIS = 19001   # every source
SINK_ADM = 19002        # every source, offset +16
SINK_RANGED = 19003     # sources 1..8 only
SINK_FROM_B = 19004     # fed from the second input only
ADM_OFFSET = 16


# ---------------------------------------------------------------- OSC codec

def _pad(b: bytes) -> bytes:
    return b + b"\0" * (4 - len(b) % 4)


def osc_encode(address: str, args) -> bytes:
    tags = ","
    body = b""
    for a in args:
        if isinstance(a, str):
            tags += "s"
            body += _pad(a.encode())
        elif isinstance(a, bool):
            tags += "T" if a else "F"
        elif isinstance(a, int):
            tags += "i"
            body += struct.pack(">i", a)
        else:
            tags += "f"
            body += struct.pack(">f", a)
    return _pad(address.encode()) + _pad(tags.encode()) + body


def osc_decode(data: bytes):
    def take_string(buf, off):
        end = buf.index(b"\0", off)
        s = buf[off:end].decode()
        return s, off + (len(s) // 4 + 1) * 4

    address, off = take_string(data, 0)
    if off >= len(data):
        return address, []
    tags, off = take_string(data, off)
    args = []
    for t in tags[1:]:
        if t == "i":
            args.append(struct.unpack_from(">i", data, off)[0]); off += 4
        elif t == "f":
            args.append(round(struct.unpack_from(">f", data, off)[0], 4)); off += 4
        elif t == "s":
            s, off = take_string(data, off); args.append(s)
        elif t == "T":
            args.append(True)
        elif t == "F":
            args.append(False)
        elif t == "d":
            args.append(round(struct.unpack_from(">d", data, off)[0], 4)); off += 8
        else:
            break
    return address, args


# ---------------------------------------------------------------- harness

class Sink(threading.Thread):
    """Collects OSC messages arriving on one UDP port."""

    def __init__(self, port):
        super().__init__(daemon=True)
        self.port = port
        self.messages = []
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", port))
        self.sock.settimeout(0.3)
        self.running = True

    def run(self):
        while self.running:
            try:
                data, _ = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            self.messages.append(osc_decode(data))

    def addresses(self):
        return [a for a, _ in self.messages]

    def find(self, address):
        return [args for addr, args in self.messages if addr == address]

    def clear(self):
        self.messages.clear()

    def stop(self):
        self.running = False
        self.sock.close()


# An ini section runs to the next line that *starts* a section, not to the next
# '[' anywhere -- the stored JSON contains plenty of those.
SECTION_RE = re.compile(r"^\[OSCRouter\]\n(.*?)(?=^\[|\Z)", re.M | re.S)


def write_section(body: str):
    original = open(CONF, encoding="utf-8").read() if os.path.exists(CONF) else ""
    section = "[OSCRouter]\n" + body
    if "[OSCRouter]" in original:
        text = re.sub(SECTION_RE, section, original, count=1)
    else:
        text = original.rstrip("\n") + "\n\n" + section
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    open(CONF, "w", encoding="utf-8").write(text)


def read_section() -> str:
    if not os.path.exists(CONF):
        return ""
    m = re.search(SECTION_RE, open(CONF, encoding="utf-8").read())
    return m.group(1) if m else ""


def quote(blob: str) -> str:
    """QSettings escapes backslashes and quotes inside a quoted value."""
    return '"' + blob.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unquote(value: str) -> str:
    return value.strip().strip('"').replace('\\"', '"').replace("\\\\", "\\")


def seed_v2():
    config = {
        "version": 2,
        "inputs": [
            {"id": 1, "name": "A", "protocol": "Auto", "port": PORT_A, "enabled": True},
            {"id": 2, "name": "B", "protocol": "Auto", "port": PORT_B, "enabled": True},
        ],
        "outputs": [
            {"id": 10, "name": "sg", "protocol": "SpatGRIS",
             "host": "127.0.0.1", "port": SINK_SPATGRIS},
            {"id": 11, "name": "adm", "protocol": "ADM-OSC",
             "host": "127.0.0.1", "port": SINK_ADM},
            {"id": 12, "name": "ranged", "protocol": "SpatGRIS",
             "host": "127.0.0.1", "port": SINK_RANGED},
            {"id": 13, "name": "fromB", "protocol": "SpatGRIS",
             "host": "127.0.0.1", "port": SINK_FROM_B},
        ],
        "routes": [
            {"inputId": 1, "outputId": 10, "enabled": True,
             "sourceOffset": 0, "srcMin": None, "srcMax": None},
            {"inputId": 1, "outputId": 11, "enabled": True,
             "sourceOffset": ADM_OFFSET, "srcMin": None, "srcMax": None},
            {"inputId": 1, "outputId": 12, "enabled": True,
             "sourceOffset": 0, "srcMin": 1, "srcMax": 8},
            # Reached only from the second input, and disabled from the first:
            # proves routes gate per input rather than per output.
            {"inputId": 1, "outputId": 13, "enabled": False,
             "sourceOffset": 0, "srcMin": None, "srcMax": None},
            {"inputId": 2, "outputId": 13, "enabled": True,
             "sourceOffset": 100, "srcMin": None, "srcMax": None},
        ],
    }
    write_section(
        "lastViewIndex=0\n"
        "logReceivedMessages=true\n"
        "logSentMessages=false\n"
        "monitorMaxRate=500\n"
        f"savedConfiguration={quote(json.dumps(config))}\n"
    )


def seed_v1():
    outputs = [
        {"name": "legacy_a", "host": "127.0.0.1", "port": SINK_SPATGRIS,
         "type": "SpatGRIS", "active": True, "sourceIndexOffset": 3},
        {"name": "legacy_b", "host": "127.0.0.1", "port": SINK_ADM,
         "type": "ADM-OSC", "active": False, "sourceIndexOffset": 0},
    ]
    write_section(
        "lastViewIndex=0\n"
        "logReceivedMessages=true\n"
        "logSentMessages=false\n"
        "monitorMaxRate=500\n"
        f"listenPort={PORT_A}\n"
        f"savedOutputDevices={quote(json.dumps(outputs))}\n"
    )


def port_is_bound(port):
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        probe.bind(("0.0.0.0", port))
        return False
    except OSError:
        return True
    finally:
        probe.close()


class App:
    """Runs the real app for the duration of a block."""

    def __enter__(self):
        subprocess.run(["pkill", "-f", "ossia-score --ui qml/Main.qml"],
                       capture_output=True)
        time.sleep(1)
        self.proc = subprocess.Popen([os.path.join(REPO, "test.sh")], cwd=REPO,
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        for _ in range(45):
            time.sleep(1)
            if port_is_bound(PORT_A):
                break
        else:
            raise RuntimeError(f"the app never bound {PORT_A}")
        time.sleep(3)  # output sockets and the second input
        return self

    def __exit__(self, *exc):
        self.proc.terminate()
        subprocess.run(["pkill", "-f", "ossia-score --ui qml/Main.qml"],
                       capture_output=True)
        time.sleep(2)  # let it write settings back
        return False


def send(port, address, args):
    tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    tx.sendto(osc_encode(address, args), ("127.0.0.1", port))
    tx.close()
    time.sleep(0.3)


# ---------------------------------------------------------------- expectations

FAILURES = []


def expect(condition, description, detail=""):
    print(f"  {'PASS' if condition else 'FAIL'}  {description}")
    if not condition:
        if detail:
            print(f"        {detail}")
        FAILURES.append(description)


def close(actual, expected, tol=1e-3):
    return len(actual) == len(expected) and all(
        (isinstance(a, str) and a == b) or
        (not isinstance(a, str) and abs(a - b) <= tol)
        for a, b in zip(actual, expected))


# ---------------------------------------------------------------- scenarios

def test_routing():
    print("\n=== routing, with a v2 configuration ===")
    seed_v2()
    sinks = {p: Sink(p) for p in
             (SINK_SPATGRIS, SINK_ADM, SINK_RANGED, SINK_FROM_B)}
    for s in sinks.values():
        s.start()
    try:
        with App():
            # -- a source inside every range -----------------------------
            print("\n/spat/serv deg 7 -90 0 1 0 0   -> input A")
            send(PORT_A, "/spat/serv", ["deg", 7, -90.0, 0.0, 1.0, 0.0, 0.0])

            sg = sinks[SINK_SPATGRIS].find("/spat/serv")
            expect(len(sg) == 1, "unfiltered SpatGRIS output receives it",
                   f"got {sinks[SINK_SPATGRIS].messages}")
            if sg:
                expect(close(sg[0], ["deg", 7, -90.0, 0.0, 1.0, 0.0, 0.0]),
                       "payload passes through verbatim", f"got {sg[0]}")

            aed = sinks[SINK_ADM].find(f"/adm/obj/{7 + ADM_OFFSET}/aed")
            expect(len(aed) == 1, "ADM output applies the route offset",
                   f"got {sinks[SINK_ADM].addresses()}")
            if aed:
                expect(close(aed[0], [90.0, 0.0, 1.0]),
                       "ADM azimuth sign is flipped", f"got {aed[0]}")

            expect(len(sinks[SINK_RANGED].find("/spat/serv")) == 1,
                   "source 7 is inside the 1-8 range and is forwarded",
                   f"got {sinks[SINK_RANGED].messages}")

            expect(not sinks[SINK_FROM_B].messages,
                   "a disabled route does not forward",
                   f"got {sinks[SINK_FROM_B].messages}")

            # -- a source outside the ranged route ------------------------
            print("\n/spat/serv deg 9 -45 0 1 0 0   -> input A")
            for s in sinks.values():
                s.clear()
            send(PORT_A, "/spat/serv", ["deg", 9, -45.0, 0.0, 1.0, 0.0, 0.0])

            expect(len(sinks[SINK_SPATGRIS].find("/spat/serv")) == 1,
                   "source 9 still reaches the unfiltered output")
            expect(not sinks[SINK_RANGED].messages,
                   "source 9 is outside 1-8 and is dropped for that route only",
                   f"got {sinks[SINK_RANGED].messages}")

            # -- the range applies to the raw ADM passthrough too ---------
            print("\n/adm/obj/9/gain 0.5 and /adm/obj/3/gain 0.5   -> input A")
            for s in sinks.values():
                s.clear()
            send(PORT_A, "/adm/obj/3/gain", [0.5])
            send(PORT_A, "/adm/obj/9/gain", [0.5])

            expect(sinks[SINK_ADM].find(f"/adm/obj/{3 + ADM_OFFSET}/gain"),
                   "raw ADM parameters are forwarded with the offset applied",
                   f"got {sinks[SINK_ADM].addresses()}")
            expect(not sinks[SINK_SPATGRIS].messages,
                   "raw ADM parameters do not reach a non-ADM output",
                   f"got {sinks[SINK_SPATGRIS].messages}")

            # -- the second input is independent ---------------------------
            print("\n/spat/serv deg 1 0 0 1 0 0   -> input B")
            for s in sinks.values():
                s.clear()
            send(PORT_B, "/spat/serv", ["deg", 1, 0.0, 0.0, 1.0, 0.0, 0.0])

            b = sinks[SINK_FROM_B].find("/spat/serv")
            expect(len(b) == 1, "input B reaches its own output",
                   f"got {sinks[SINK_FROM_B].messages}")
            if b:
                expect(b[0][1] == 101, "input B applies its own +100 offset",
                       f"got index {b[0][1]}")
            expect(not sinks[SINK_SPATGRIS].messages,
                   "input B does not leak into input A's outputs",
                   f"got {sinks[SINK_SPATGRIS].messages}")

            # -- per-input ADM accumulators --------------------------------
            print("\n/adm/obj/1/xyz on both inputs, then /adm/obj/1/x on A")
            for s in sinks.values():
                s.clear()
            send(PORT_A, "/adm/obj/1/xyz", [0.1, 0.2, 0.3])
            send(PORT_B, "/adm/obj/1/xyz", [0.6, 0.7, 0.8])
            for s in sinks.values():
                s.clear()
            send(PORT_A, "/adm/obj/1/x", [0.5])

            a_sg = sinks[SINK_SPATGRIS].find("/spat/serv")
            expect(len(a_sg) == 1, "A's ADM update reaches A's output",
                   f"got {sinks[SINK_SPATGRIS].messages}")
            if a_sg:
                expect(close(a_sg[0][2:5], [0.5, 0.2, 0.3]),
                       "A keeps its own y and z — accumulators are per input",
                       f"got {a_sg[0]}")
    finally:
        for s in sinks.values():
            s.stop()


def test_v1_migration():
    print("\n=== migration from a v1 configuration ===")
    seed_v1()
    with App():
        pass

    section = read_section()
    m = re.search(r"savedConfiguration=(.*)", section)
    expect(m is not None, "a v2 configuration is written on first launch")
    if not m:
        return
    cfg = json.loads(unquote(m.group(1)))

    expect(cfg.get("version") == 2, "it is tagged version 2", f"got {cfg.get('version')}")
    expect(len(cfg["inputs"]) == 1, "the implicit input becomes one real input",
           f"got {cfg['inputs']}")
    expect(cfg["inputs"][0]["port"] == PORT_A,
           "it keeps the old listen port", f"got {cfg['inputs'][0]}")
    expect(cfg["inputs"][0].get("enabled") is True,
           "and is enabled, so the next launch still listens",
           f"got {cfg['inputs'][0]}")

    expect(len(cfg["outputs"]) == 2, "both saved outputs survive",
           f"got {cfg['outputs']}")
    names = sorted(o["name"] for o in cfg["outputs"])
    expect(names == ["legacy_a", "legacy_b"], "with their names",
           f"got {names}")

    by_name = {o["id"]: o["name"] for o in cfg["outputs"]}
    routes = {by_name[r["outputId"]]: r for r in cfg["routes"]}
    expect(len(cfg["routes"]) == 2, "each output gains a route from that input",
           f"got {cfg['routes']}")
    expect(routes["legacy_a"]["sourceOffset"] == 3,
           "the per-output offset moves onto the route",
           f"got {routes['legacy_a']}")
    expect(routes["legacy_a"]["enabled"] is True,
           "an active output becomes an enabled route")
    expect(routes["legacy_b"]["enabled"] is False,
           "an inactive output becomes a disabled route",
           f"got {routes['legacy_b']}")
    expect(all(r["srcMin"] is None and r["srcMax"] is None
               for r in cfg["routes"]),
           "migrated routes carry every source")

    expect("savedOutputDevices=" in section,
           "the v1 keys are left in place for a rollback")


def main():
    original = open(CONF, encoding="utf-8").read() if os.path.exists(CONF) else None
    try:
        test_routing()
        test_v1_migration()
    finally:
        subprocess.run(["pkill", "-f", "ossia-score --ui qml/Main.qml"],
                       capture_output=True)
        if original is not None:
            open(CONF, "w", encoding="utf-8").write(original)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} expectation(s) failed")
        return 1
    print("all expectations met")
    return 0


if __name__ == "__main__":
    sys.exit(main())
