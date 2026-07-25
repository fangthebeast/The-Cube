# Cube firmware

ESP32 + MPU6050 firmware for the physical cube. Built and flashed with the
Arduino IDE / `arduino-cli`, not PlatformIO.

| Sketch | Purpose |
| --- | --- |
| `CubeBLE/` | **The live firmware.** Face + tap detection over BLE. |
| `CubeFaceTap/` | Serial-only face + tap detection. Kept as a known-good reference for debugging the sensor without BLE in the way. |

## Hardware

ESP32-D + GY-521 (MPU6050) breakout:

```
VCC -> 3.3V     SDA -> GPIO21
GND -> GND      SCL -> GPIO22
AD0 -> GND      (I2C address 0x68)
```

`AD0` is tied straight to ground rather than driven from a GPIO. A flaky ground
connection here was once the root cause of I2C bus timeouts and garbled serial —
check it first if readings go strange.

## BLE contract

`CubeBLE` serves what both iOS apps expect. The UUIDs must stay in sync with
`CubeBLEManager.swift` in each app.

Service `4FAFC201-1FB5-459E-8FCC-C5C9C331914B`

| Characteristic | UUID | Properties | Payload |
| --- | --- | --- | --- |
| Face | `BEB5483E-…-EA07361B26A8` | read, notify | `uint8` face index 0–5 |
| Event | `BEB5483E-…-EA07361B26A9` | notify | `0x01` roll settled, `0x02` double tap |
| LED | `BEB5483E-…-EA07361B26AA` | write | `uint8` LEDCommand 0–5 |

`TodayCube` only discovers the face characteristic; `WorkHardPlayHardCube` uses
all three.

Notes that are easy to get wrong:

- **Face index, not pips.** The apps want 0–5, matching `Mode.allCases` order.
  Detection produces die pips 1–6, so the firmware subtracts one.
- **Face is notified before the roll event.** `AppStore.registerRoll(face:)`
  receives `nil` for real roll events and falls back to `currentFace`, so the
  landed face has to arrive first or the app logs the previous one.
- **The advertised name is short (`Cube`) on purpose.** A 128-bit service UUID
  takes 18 of the 31 advertising bytes; a longer name overflows the packet and
  the cube stops being discoverable. Both apps scan by service UUID, so the
  name is cosmetic.
- **LED colours are approximated.** No RGB LED is wired yet, so each command
  gets a distinguishable blink rhythm on the onboard LED (GPIO2). Swap
  `applyLED()` for NeoPixel writes when the real LED lands.

## Build and flash

```
arduino-cli compile --fqbn esp32:esp32:esp32 firmware/CubeBLE
arduino-cli upload -p /dev/cu.usbserial-0001 --fqbn esp32:esp32:esp32 firmware/CubeBLE
```

Needs the `esp32:esp32` core (built against 3.3.11). `CubeBLE` lands at ~85% of
the default partition, so no `huge_app` scheme is required. Close the Arduino
IDE Serial Monitor before uploading — it holds the port and the upload fails
with "Resource busy".

Serial output is 115200 baud.

## Verifying

`CubeBLE/verify_cube.py` connects as a BLE central and checks the whole
contract — scans by service UUID, verifies all three characteristics and their
properties, reads the face value, subscribes to notifications, and writes an
LED command. It needs Python with `bleak`:

```
python3 -m venv .venv && .venv/bin/pip install bleak
.venv/bin/python firmware/CubeBLE/verify_cube.py 30
```

On macOS the process is killed with SIGABRT unless the terminal application has
been granted Bluetooth access under System Settings → Privacy & Security →
Bluetooth.

Note that the **iOS Simulator has no CoreBluetooth support** — the cube will
never appear there. Testing against the real apps requires a physical iPhone.
A generic BLE scanner app (nRF Connect, LightBlue) is the quickest way to check
advertising and notifications without building anything.
