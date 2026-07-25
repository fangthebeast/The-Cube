#!/usr/bin/env python3
"""Verify the cube firmware against the contract CubeBLEManager.swift expects.

Does the same sequence the iOS app does: scan by service UUID, connect,
discover characteristics, read the face value, subscribe to notifications,
and write the LED characteristic.
"""
import asyncio
import sys
import time

from bleak import BleakClient, BleakScanner

SERVICE = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
FACE = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
EVENT = "beb5483e-36e1-4688-b7f5-ea07361b26a9"
LED = "beb5483e-36e1-4688-b7f5-ea07361b26aa"

# Face index -> Mode, in Mode.allCases order. Face 5 differs between the apps.
MODES = ["deepWork", "move", "create", "social", "rest", "admin/hydrate"]
EVENTS = {0x01: "ROLL SETTLED", 0x02: "DOUBLE TAP"}

LISTEN_SECONDS = int(sys.argv[1]) if len(sys.argv) > 1 else 30
start = time.monotonic()


def stamp():
    return f"[{time.monotonic() - start:6.2f}s]"


async def main():
    print(f"Scanning for service {SERVICE} ...")
    device = await BleakScanner.find_device_by_filter(
        lambda d, ad: SERVICE in [str(u).lower() for u in ad.service_uuids],
        timeout=15.0,
    )

    if device is None:
        print("FAIL: no peripheral advertising that service UUID.\n")
        print("Everything else in range, for reference:")
        for d in await BleakScanner.discover(timeout=8.0):
            print(f"  {d.address}  {d.name!r}")
        print("\nIf the cube is absent entirely, it isn't advertising.")
        print("If it appears but without the service UUID, advertising is misconfigured.")
        return 1

    print(f"PASS: found {device.name!r} ({device.address})")

    async with BleakClient(device) as client:
        print(f"PASS: connected (the firmware should now log 'BLE: app connected')")

        service = next(
            (s for s in client.services if s.uuid.lower() == SERVICE), None
        )
        if service is None:
            print("FAIL: service not present after connecting")
            return 1

        found = {c.uuid.lower(): c for c in service.characteristics}
        ok = True
        for name, uuid, want in (
            ("face ", FACE, "notify"),
            ("event", EVENT, "notify"),
            ("led  ", LED, "write"),
        ):
            char = found.get(uuid)
            if char is None:
                print(f"FAIL: {name} characteristic {uuid} missing")
                ok = False
                continue
            props = ",".join(char.properties)
            has = any(want in p for p in char.properties)
            print(f"{'PASS' if has else 'FAIL'}: {name} {uuid}  props=[{props}]")
            ok = ok and has
        if not ok:
            return 1

        value = await client.read_gatt_char(FACE)
        idx = value[0]
        label = MODES[idx] if idx < len(MODES) else "OUT OF RANGE"
        print(f"PASS: face read = {idx} ({label})")

        def on_face(_, data: bytearray):
            i = data[0]
            name = MODES[i] if i < len(MODES) else "OUT OF RANGE!"
            print(f"{stamp()} FACE  -> {i}  ({name})")

        def on_event(_, data: bytearray):
            print(f"{stamp()} EVENT -> 0x{data[0]:02x}  ({EVENTS.get(data[0], 'UNKNOWN')})")

        await client.start_notify(FACE, on_face)
        await client.start_notify(EVENT, on_event)
        print("PASS: subscribed to face + event\n")

        print("Writing LED 0x04 (partyPulse) — onboard LED should strobe fast")
        await client.write_gatt_char(LED, bytes([0x04]), response=True)

        print(f"\n--- listening {LISTEN_SECONDS}s: flip the cube, double-tap it, roll it ---")
        await asyncio.sleep(LISTEN_SECONDS)

        print("\nWriting LED 0x00 (off)")
        await client.write_gatt_char(LED, bytes([0x00]), response=True)
        await client.stop_notify(FACE)
        await client.stop_notify(EVENT)

    print("\nDisconnected. Firmware should log 'BLE: app disconnected, advertising again'.")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
