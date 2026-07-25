// ESP32 + MPU6050 cube firmware, USB serial out.
//
// Same face/tap/roll detection as CubeBLE, with BLE stripped out and the
// results emitted as newline-delimited lines a web page can parse over the
// Web Serial API. Being on the wire means no advertising, no pairing and no
// Bluetooth permissions — the browser opens the port and reads.
//
// Protocol, 115200 baud. One event per line, readable in a serial monitor:
//
//   CUBE READY      once at boot
//   FACE <0-5>      the settled face changed; index matches Mode.allCases
//   ROLL <0-5>      a single tap — commits whatever face is up as a roll
//   TAP             a double tap — one drink
//
// Rolling is a single tap rather than a physical tumble: land the cube on the
// face you want, tap once, and that face is the roll. Tumble detection was
// too easy to trip by nudging the cube on a crowded table.
//
// Wiring: VCC->3.3V, GND->GND, SDA->GPIO21, SCL->GPIO22, AD0->GND (addr 0x68)

#include <Wire.h>

const int MPU_ADDR = 0x68;
int16_t ax, ay, az;

// --- Tap detection ---
const float TAP_THRESHOLD_G = 1.8;
const unsigned long TAP_DEBOUNCE_MS = 150;
const unsigned long DOUBLE_TAP_WINDOW_MS = 400;
unsigned long lastTapEdgeTime = 0;
bool waitingForSecondTap = false;
unsigned long firstTapTime = 0;

// A tumbling cube spikes past the tap threshold repeatedly, so a tap only
// counts if the cube was sitting still just before it.
const unsigned long TAP_REQUIRE_REST_MS = 120;

// --- Motion / roll detection ---
const float REST_BAND_G = 0.15;
const float ROLL_MOTION_G = 0.35;
const unsigned long ROLL_SETTLE_MS = 500;

bool inMotion = false;
unsigned long lastMotionAt = 0;
unsigned long quietSince = 0;

// --- Face reporting ---
const unsigned long FACE_STABLE_MS = 400;
int8_t candidateFace = -1;
unsigned long candidateSince = 0;
int8_t reportedFace = -1;

void mpuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

void readAccel() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 6, true);
  ax = Wire.read() << 8 | Wire.read();
  ay = Wire.read() << 8 | Wire.read();
  az = Wire.read() << 8 | Wire.read();
}

// Die-style face numbering (opposite faces sum to 7):
//   Top = 5, Bottom = 2, Front = 1, Back = 6, Right = 4, Left = 3
int faceFromAccel(float gx, float gy, float gz) {
  float ax_abs = fabs(gx), ay_abs = fabs(gy), az_abs = fabs(gz);

  if (az_abs > ax_abs && az_abs > ay_abs) {
    return (gz > 0) ? 5 : 2;   // Top : Bottom
  } else if (ay_abs > ax_abs && ay_abs > az_abs) {
    return (gy > 0) ? 1 : 6;   // Front : Back
  } else {
    return (gx > 0) ? 4 : 3;   // Right : Left
  }
}

// The app speaks face index 0-5; detection produces die pips 1-6.
uint8_t faceIndexFromPips(int pips) {
  return (uint8_t)(pips - 1);
}

void reportFace(uint8_t faceIndex) {
  reportedFace = (int8_t)faceIndex;
  Serial.print("FACE ");
  Serial.println(faceIndex);
}

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  mpuWrite(0x6B, 0x00); // wake MPU6050
  delay(100);
  Serial.println("CUBE READY");
}

void loop() {
  readAccel();

  float gx = ax / 16384.0;
  float gy = ay / 16384.0;
  float gz = az / 16384.0;
  float mag = sqrt(gx * gx + gy * gy + gz * gz);
  float dev = fabs(mag - 1.0);

  unsigned long now = millis();

  // Read the quiet duration before this sample updates it, so a tap spike is
  // judged on the stillness that preceded it.
  unsigned long quietFor = (quietSince == 0) ? 0 : (now - quietSince);

  // --- Taps ---
  if (mag > TAP_THRESHOLD_G && (now - lastTapEdgeTime) > TAP_DEBOUNCE_MS
      && quietFor >= TAP_REQUIRE_REST_MS) {
    lastTapEdgeTime = now;

    if (waitingForSecondTap && (now - firstTapTime) < DOUBLE_TAP_WINDOW_MS) {
      Serial.println("TAP");
      waitingForSecondTap = false;
    } else {
      waitingForSecondTap = true;
      firstTapTime = now;
    }
  }

  // No second tap inside the window, so that was a single tap — a roll.
  // Whatever face is up is the one being committed.
  if (waitingForSecondTap && (now - firstTapTime) > DOUBLE_TAP_WINDOW_MS) {
    waitingForSecondTap = false;
    int8_t face = (reportedFace >= 0)
      ? reportedFace
      : (int8_t)faceIndexFromPips(faceFromAccel(gx, gy, gz));
    Serial.print("ROLL ");
    Serial.println(face);
  }

  // --- Motion ---
  if (dev > ROLL_MOTION_G) {
    inMotion = true;
    lastMotionAt = now;
    quietSince = 0;
  } else if (dev < REST_BAND_G) {
    if (quietSince == 0) quietSince = now;
  }

  bool settled = (dev < REST_BAND_G) && (quietSince != 0) && (now - quietSince) > ROLL_SETTLE_MS;

  // --- Face changes ---
  if (settled) {
    int8_t face = (int8_t)faceIndexFromPips(faceFromAccel(gx, gy, gz));
    if (face != candidateFace) {
      candidateFace = face;
      candidateSince = now;
    } else if (face != reportedFace && (now - candidateSince) > FACE_STABLE_MS) {
      reportFace((uint8_t)face);
    }
  }

  // Motion still gets tracked, but only to gate taps — a tumbling cube must
  // not read as tapping. Coming to rest no longer emits a roll on its own.
  if (inMotion && settled) inMotion = false;

  delay(5);
}
