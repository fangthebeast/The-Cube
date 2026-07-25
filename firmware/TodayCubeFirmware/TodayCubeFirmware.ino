// Today Cube firmware — face detection + tap detection + BLE + LED (2026-07-24)
//
// Built on the partner's original MPU6050 sketch (kept intact where possible),
// with the BLE layer the iOS app expects:
//
//   Service            4fafc201-1fb5-459e-8fcc-c5c9c331914b
//   Face char (notify) beb5483e-36e1-4688-b7f5-ea07361b26a8  → UInt8 pip value 1–6, sent when settled face changes
//   Event char(notify) beb5483f-36e1-4688-b7f5-ea07361b26a8  → 0x01 roll-settled, 0x02 double-tap
//   LED char  (write)  beb54840-36e1-4688-b7f5-ea07361b26a8  → 0 off, 1 red, 2 yellow, 3 green, 4 blue party pulse, 5 green celebration blink
//
// Wiring (MPU6050): VCC->3.3V, GND->GND, SDA->GPIO21, SCL->GPIO22, AD0->GND (addr 0x68)
// Wiring (LEDs): ⚠️ ADJUST PINS BELOW to match the actual solder job.
//
// Board package: "ESP32 by Espressif" in Arduino IDE (includes BLEDevice.h).

#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================== TUNING =====================================
const int MPU_ADDR = 0x68;

// Tap detection
const float TAP_THRESHOLD_G = 1.8;
const unsigned long TAP_DEBOUNCE_MS = 150;
const unsigned long DOUBLE_TAP_WINDOW_MS = 400;

// Roll detection: sustained motion, then stillness = a roll has settled.
const float MOTION_DEV_G = 0.35;            // |mag - 1g| above this = moving
const float STILL_DEV_G = 0.15;             // |mag - 1g| below this = still
const unsigned long MIN_ROLL_MS = 400;      // motion shorter than this = a tap, not a roll
const unsigned long SETTLE_MS = 600;        // must be still this long before roll counts as settled
const unsigned long TAP_SUPPRESS_MS = 300;  // suppress tap events once motion has lasted this long (mid-roll spikes aren't taps)

// LED pins — ⚠️ ADJUST to actual wiring (4 discrete LEDs assumed; active HIGH)
const int LED_RED_PIN = 25;
const int LED_YELLOW_PIN = 26;
const int LED_GREEN_PIN = 27;
const int LED_BLUE_PIN = 32;

// BLE UUIDs — must match CubeBLEManager.swift in the iOS app
#define SERVICE_UUID     "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define FACE_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define EVENT_CHAR_UUID  "beb5483f-36e1-4688-b7f5-ea07361b26a8"
#define LED_CHAR_UUID    "beb54840-36e1-4688-b7f5-ea07361b26a8"

const uint8_t EVENT_ROLL_SETTLED = 0x01;
const uint8_t EVENT_DOUBLE_TAP   = 0x02;

// ============================== STATE ======================================
int16_t ax, ay, az;

unsigned long lastTapEdgeTime = 0;
bool waitingForSecondTap = false;
unsigned long firstTapTime = 0;

bool inMotion = false;
unsigned long motionStartTime = 0;
unsigned long stillSinceTime = 0;

int lastSentFace = 0;                 // 0 = nothing sent yet
unsigned long lastFaceCheck = 0;
const unsigned long FACE_CHECK_INTERVAL_MS = 200;

// LED state machine (non-blocking animations)
volatile uint8_t ledMode = 0;         // 0 off, 1 red, 2 yellow, 3 green, 4 party pulse (blue), 5 celebration blink (green)
unsigned long lastLedToggle = 0;
bool ledBlinkOn = false;

// BLE
BLEServer *server = nullptr;
BLECharacteristic *faceChar = nullptr;
BLECharacteristic *eventChar = nullptr;
bool deviceConnected = false;

// ============================== BLE CALLBACKS ==============================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *s) override { deviceConnected = true; }
  void onDisconnect(BLEServer *s) override {
    deviceConnected = false;
    s->getAdvertising()->start();     // keep advertising so the app auto-reconnects
  }
};

class LedCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    if (c->getLength() >= 1) {
      uint8_t v = c->getData()[0];
      if (v <= 5) {
        ledMode = v;
        Serial.print("LED mode <- ");
        Serial.println(v);
      }
    }
  }
};

// ============================== MPU HELPERS ================================
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
// Adjust axis→face mapping to match how the MPU6050 is mounted in the cube.
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

// ============================== NOTIFY HELPERS =============================
void notifyFace(uint8_t face) {
  Serial.print("Face up: ");
  Serial.println(face);
  if (deviceConnected && faceChar) {
    faceChar->setValue(&face, 1);
    faceChar->notify();
  }
}

void notifyEvent(uint8_t code) {
  Serial.print("Event: 0x");
  Serial.println(code, HEX);
  if (deviceConnected && eventChar) {
    eventChar->setValue(&code, 1);
    eventChar->notify();
  }
}

// ============================== LED ========================================
void setLeds(bool r, bool y, bool g, bool b) {
  digitalWrite(LED_RED_PIN, r);
  digitalWrite(LED_YELLOW_PIN, y);
  digitalWrite(LED_GREEN_PIN, g);
  digitalWrite(LED_BLUE_PIN, b);
}

void updateLeds(unsigned long now) {
  switch (ledMode) {
    case 0: setLeds(0, 0, 0, 0); break;
    case 1: setLeds(1, 0, 0, 0); break;                    // red solid
    case 2: setLeds(0, 1, 0, 0); break;                    // yellow solid
    case 3: setLeds(0, 0, 1, 0); break;                    // green solid
    case 4:                                                // party: blue pulse (slow blink)
      if (now - lastLedToggle > 500) { lastLedToggle = now; ledBlinkOn = !ledBlinkOn; }
      setLeds(0, 0, 0, ledBlinkOn);
      break;
    case 5:                                                // celebration: green fast blink
      if (now - lastLedToggle > 120) { lastLedToggle = now; ledBlinkOn = !ledBlinkOn; }
      setLeds(0, 0, ledBlinkOn, 0);
      break;
  }
}

// ============================== SETUP ======================================
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  mpuWrite(0x6B, 0x00); // wake MPU6050
  delay(100);

  pinMode(LED_RED_PIN, OUTPUT);
  pinMode(LED_YELLOW_PIN, OUTPUT);
  pinMode(LED_GREEN_PIN, OUTPUT);
  pinMode(LED_BLUE_PIN, OUTPUT);
  setLeds(0, 0, 0, 0);

  BLEDevice::init("TodayCube");
  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  faceChar = service->createCharacteristic(
      FACE_CHAR_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  faceChar->addDescriptor(new BLE2902());

  eventChar = service->createCharacteristic(
      EVENT_CHAR_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  eventChar->addDescriptor(new BLE2902());

  BLECharacteristic *ledChar = service->createCharacteristic(
      LED_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  ledChar->setCallbacks(new LedCallbacks());

  service->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();

  Serial.println("TodayCube BLE advertising.");
}

// ============================== LOOP =======================================
void loop() {
  readAccel();

  float gx = ax / 16384.0;
  float gy = ay / 16384.0;
  float gz = az / 16384.0;
  float mag = sqrt(gx * gx + gy * gy + gz * gz);
  float dev = fabs(mag - 1.0);
  unsigned long now = millis();

  // --- Motion / roll state machine ---
  bool sustainedMotion = inMotion && (now - motionStartTime > TAP_SUPPRESS_MS);

  if (dev > MOTION_DEV_G) {
    if (!inMotion) { inMotion = true; motionStartTime = now; }
    stillSinceTime = 0;
    if (sustainedMotion) waitingForSecondTap = false; // mid-roll spikes are not taps
  } else if (dev < STILL_DEV_G) {
    if (inMotion) {
      if (stillSinceTime == 0) stillSinceTime = now;
      if (now - stillSinceTime > SETTLE_MS) {
        unsigned long motionDuration = stillSinceTime - motionStartTime;
        inMotion = false;
        if (motionDuration > MIN_ROLL_MS) {
          notifyEvent(EVENT_ROLL_SETTLED);         // roll settled; app reads the face next
          lastSentFace = 0;                        // force a fresh face notify below
        }
      }
    }
  }

  // --- Tap detection (suppressed during sustained motion, i.e. rolls) ---
  if (!sustainedMotion && mag > TAP_THRESHOLD_G && (now - lastTapEdgeTime) > TAP_DEBOUNCE_MS) {
    lastTapEdgeTime = now;
    if (waitingForSecondTap && (now - firstTapTime) < DOUBLE_TAP_WINDOW_MS) {
      notifyEvent(EVENT_DOUBLE_TAP);
      waitingForSecondTap = false;
    } else {
      waitingForSecondTap = true;
      firstTapTime = now;
    }
  }
  if (waitingForSecondTap && (now - firstTapTime) > DOUBLE_TAP_WINDOW_MS) {
    waitingForSecondTap = false;
    Serial.println(">>> single tap <<<"); // single taps stay local; app doesn't use them
  }

  // --- Face reporting: only when settled, only on change ---
  if (now - lastFaceCheck > FACE_CHECK_INTERVAL_MS) {
    lastFaceCheck = now;
    if (dev < STILL_DEV_G && !inMotion) {
      int face = faceFromAccel(gx, gy, gz);        // pip value 1–6; app converts to its 0–5 index
      if (face != lastSentFace) {
        lastSentFace = face;
        notifyFace((uint8_t)face);
      }
    }
  }

  updateLeds(now);
  delay(5);
}
