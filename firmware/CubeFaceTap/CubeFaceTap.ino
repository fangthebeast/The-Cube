// ESP32 + MPU6050: detect which face of a cube is facing down, and detect
// single vs. double taps.
// - Face detection: static reading, whichever axis is aligned with gravity.
// - Tap detection: MPU6050 has no dedicated hardware tap interrupt (unlike
//   ADXL345/LIS3DH), so this does it in software — watch for a short, sharp
//   spike in acceleration magnitude above a threshold, debounce, then check
//   if a second spike follows within DOUBLE_TAP_WINDOW_MS.
// Wiring: VCC->3.3V, GND->GND, SDA->GPIO21, SCL->GPIO22, AD0->GND (addr 0x68)

#include <Wire.h>

const int MPU_ADDR = 0x68;
int16_t ax, ay, az;

// --- Tap detection tuning ---
const float TAP_THRESHOLD_G = 1.8;   // total accel magnitude spike above this = one tap edge (tune per mounting)
const unsigned long TAP_DEBOUNCE_MS = 150;      // ignore retriggers within this window (one physical tap can spike more than once)
const unsigned long DOUBLE_TAP_WINDOW_MS = 400; // max gap between two taps to count as a double-tap
unsigned long lastTapEdgeTime = 0;   // last time we accepted a raw tap edge
bool waitingForSecondTap = false;
unsigned long firstTapTime = 0;

// --- Face detection tuning ---
unsigned long lastFacePrint = 0;
const unsigned long FACE_PRINT_INTERVAL_MS = 200;

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

// Die-style face numbering (opposite faces sum to 7, like a standard die):
//   Top = 5, Bottom = 2, Front = 1, Back = 6, Right = 4, Left = 3
// Adjust which chip-axis maps to which physical face to match how the
// MPU6050 is actually mounted inside your cube.
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

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  mpuWrite(0x6B, 0x00); // wake MPU6050
  delay(100);
}

void loop() {
  readAccel();

  float gx = ax / 16384.0; // g
  float gy = ay / 16384.0;
  float gz = az / 16384.0;
  float mag = sqrt(gx * gx + gy * gy + gz * gz);

  // --- Tap detection: fast poll, look for a sharp spike above threshold ---
  unsigned long now = millis();

  if (mag > TAP_THRESHOLD_G && (now - lastTapEdgeTime) > TAP_DEBOUNCE_MS) {
    lastTapEdgeTime = now;

    if (waitingForSecondTap && (now - firstTapTime) < DOUBLE_TAP_WINDOW_MS) {
      Serial.println(">>> DOUBLE TAP <<<");
      waitingForSecondTap = false; // consumed, don't let a 3rd tap chain onto this
    } else {
      waitingForSecondTap = true;
      firstTapTime = now;
    }
  }

  // If we were waiting for a second tap and the window expired, it was just a single tap
  if (waitingForSecondTap && (now - firstTapTime) > DOUBLE_TAP_WINDOW_MS) {
    waitingForSecondTap = false;
    Serial.println(">>> single tap <<<");
  }

  // --- Face detection: only report when settled (near 1g, not mid-tap/motion) ---
  if (now - lastFacePrint > FACE_PRINT_INTERVAL_MS) {
    lastFacePrint = now;
    if (fabs(mag - 1.0) < 0.15) {
      Serial.print("Face up: ");
      Serial.println(faceFromAccel(gx, gy, gz));
    }
  }

  delay(5); // fast sampling so short taps aren't missed
}
