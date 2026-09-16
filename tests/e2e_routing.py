#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# © Société des arts technologiques
"""
End-to-end routing test: drives the real app over UDP.

tst_engine.qml covers the conversion table as pure functions. This covers the
part it cannot reach — the input socket, the OSC parser, per-output sockets and
the source-index offset — by seeding a known configuration, launching the app,
sending OSC at the listen port and asserting on what comes out the other side.

Not part of CI: it needs a built ossia-score (see ./test.sh). Run it locally
before and after touching the routing engine.

    python3 tests/e2e_routing.py

Exits non-zero on the first failed expectation.
"""

import json
import os
import re
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONF = os.path.expanduser("~/.config/ossia/score.conf")
LISTEN_PORT = 18032
SPATGRIS_PORT = 19001
ADM_PORT = 19002
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
        elif t in "d":
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

    def stop(self):
        self.running = False
        self.sock.close()


def seed_settings():
    """Point the app at our two sinks; returns the original file contents."""
    original = open(CONF, encoding="utf-8").read() if os.path.exists(CONF) else None

    outputs = [
        {"name": "sg", "host": "127.0.0.1", "port": SPATGRIS_PORT,
         "type": "SpatGRIS", "active": True, "sourceIndexOffset": 0},
        {"name": "adm", "host": "127.0.0.1", "port": ADM_PORT,
         "type": "ADM-OSC", "active": True, "sourceIndexOffset": ADM_OFFSET},
    ]
    # QSettings escapes the JSON string; mirror what the app writes back.
    blob = json.dumps(outputs).replace("\\", "\\\\").replace('"', '\\"')
    section = (
        "[OSCRouter]\n"
        "lastViewIndex=0\n"
        f"listenPort={LISTEN_PORT}\n"
        "logReceivedMessages=true\n"
        "logSentMessages=false\n"
        "monitorMaxRate=500\n"
        f'savedOutputDevices="{blob}"\n'
    )

    text = original or ""
    if "[OSCRouter]" in text:
        text = re.sub(r"\[OSCRouter\]\n(?:[^\[]*)", section, text, count=1)
    else:
        text = text.rstrip("\n") + "\n\n" + section
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    open(CONF, "w", encoding="utf-8").write(text)
    return original


def restore_settings(original):
    if original is None:
        os.path.exists(CONF) and os.remove(CONF)
    else:
        open(CONF, "w", encoding="utf-8").write(original)


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


# ---------------------------------------------------------------- expectations

FAILURES = []


def expect(condition, description, detail=""):
    if condition:
        print(f"  PASS  {description}")
    else:
        print(f"  FAIL  {description}")
        if detail:
            print(f"        {detail}")
        FAILURES.append(description)


def find(messages, address):
    return [args for addr, args in messages if addr == address]


def close(actual, expected, tol=1e-3):
    return len(actual) == len(expected) and all(
        (isinstance(a, str) and a == b) or
        (not isinstance(a, str) and abs(a - b) <= tol)
        for a, b in zip(actual, expected))


def main():
    subprocess.run(["pkill", "-f", "ossia-score --ui qml/Main.qml"],
                   capture_output=True)
    time.sleep(1)

    original = seed_settings()
    sinks = [Sink(SPATGRIS_PORT), Sink(ADM_PORT)]
    for s in sinks:
        s.start()

    app = subprocess.Popen([os.path.join(REPO, "test.sh")], cwd=REPO,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        print(f"waiting for the app to bind {LISTEN_PORT} ...")
        for _ in range(40):
            time.sleep(1)
            if port_is_bound(LISTEN_PORT):
                break
        else:
            print("FAIL: the app never bound the listen port")
            return 1
        time.sleep(2)  # let the output sockets open too

        tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        def send(address, args):
            tx.sendto(osc_encode(address, args), ("127.0.0.1", LISTEN_PORT))
            time.sleep(0.25)

        # --- a ControlGRIS source at the extreme left, in degrees ---------
        print("\n/spat/serv deg 7 -90 0 1 0 0")
        send("/spat/serv", ["deg", 7, -90.0, 0.0, 1.0, 0.0, 0.0])

        sg = find(sinks[0].messages, "/spat/serv")
        expect(len(sg) == 1, "SpatGRIS output receives one /spat/serv",
               f"got {sinks[0].messages}")
        if sg:
            expect(close(sg[0], ["deg", 7, -90.0, 0.0, 1.0, 0.0, 0.0]),
                   "SpatGRIS payload passes through verbatim", f"got {sg[0]}")

        aed = find(sinks[1].messages, f"/adm/obj/{7 + ADM_OFFSET}/aed")
        expect(len(aed) == 1,
               f"ADM output receives /adm/obj/{7 + ADM_OFFSET}/aed (offset applied)",
               f"got {sinks[1].messages}")
        if aed:
            expect(close(aed[0], [90.0, 0.0, 1.0]),
                   "ADM azimuth sign is flipped", f"got {aed[0]}")

        # --- cartesian, checking the MBAP -> normalized scaling ------------
        print("\n/spat/serv car 1 1.6666667 0 0 0 0")
        for s in sinks:
            s.messages.clear()
        send("/spat/serv", ["car", 1, 1.6666667, 0.0, 0.0, 0.0, 0.0])

        xyz = find(sinks[1].messages, f"/adm/obj/{1 + ADM_OFFSET}/xyz")
        expect(len(xyz) == 1, "ADM output receives packed /xyz",
               f"got {sinks[1].messages}")
        if xyz:
            expect(close(xyz[0], [1.0, 0.0, 0.0]),
                   "full-scale MBAP x maps onto the ADM unit sphere", f"got {xyz[0]}")

        # --- ADM input, exercising the other parser ------------------------
        print("\n/adm/obj/3/aed 90 0 1")
        for s in sinks:
            s.messages.clear()
        send("/adm/obj/3/aed", [90.0, 0.0, 1.0])

        sg = find(sinks[0].messages, "/spat/serv")
        expect(len(sg) == 1, "an ADM input reaches the SpatGRIS output",
               f"got {sinks[0].messages}")
        if sg:
            expect(close(sg[0], ["deg", 3, -90.0, 0.0, 1.0, 0.0, 0.0]),
                   "ADM azimuth is flipped into SpatGRIS convention", f"got {sg[0]}")

        # --- raw ADM passthrough, which carries its own offset logic -------
        print("\n/adm/obj/3/gain 0.5  (untranslatable, forwarded raw)")
        for s in sinks:
            s.messages.clear()
        send("/adm/obj/3/gain", [0.5])

        gain = find(sinks[1].messages, f"/adm/obj/{3 + ADM_OFFSET}/gain")
        expect(len(gain) == 1,
               "raw ADM parameters are forwarded with the offset applied",
               f"got {sinks[1].messages}")
        expect(not find(sinks[0].messages, "/spat/serv"),
               "raw ADM parameters do not reach a non-ADM output",
               f"got {sinks[0].messages}")

    finally:
        app.terminate()
        subprocess.run(["pkill", "-f", "ossia-score --ui qml/Main.qml"],
                       capture_output=True)
        for s in sinks:
            s.stop()
        time.sleep(1)
        restore_settings(original)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} expectation(s) failed")
        return 1
    print("all expectations met")
    return 0


if __name__ == "__main__":
    sys.exit(main())
