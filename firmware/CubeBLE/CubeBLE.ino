// ESP32 + MPU6050 cube firmware, BLE peripheral.
//
// Serves the contract both iOS apps expect (TodayCube and WorkHardPlayHardCube):
//
//   Service  4FAFC201-1FB5-459E-8FCC-C5C9C331914B
//     Face   BEB5483E-36E1-4688-B7F5-EA07361B26A8  read + notify   uint8 face index 0-5
//     Event  BEB5483E-36E1-4688-B7F5-EA07361B26A9  notify          uint8 0x01 roll settled, 0x02 double tap
//     LED    BEB5483E-36E1-4688-B7F5-EA07361B26AA  write           uint8 LEDCommand 0-5
//
// TodayCube only discovers the face characteristic, so the extra two are
// harmless there. WorkHardPlayHardCube uses all three.
//
// Face detection and tap detection are the same approach as the standalone
// sketch: gravity-dominant axis for the face, software spike detection for
// taps (the MPU6050 has no hardware tap interrupt).
//
// Wiring: VCC->3.3V, GND->GND, SDA->GPIO21, SCL->GPIO22, AD0->GND (addr 0x68)

#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- BLE contract (must match CubeBLEManager.swift in both apps) ---
#define SERVICE_UUID    "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define FACE_CHAR_UUID  "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
#define EVENT_CHAR_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A9"
#define LED_CHAR_UUID   "BEB5483E-36E1-4688-B7F5-EA07361B26AA"

// Event payloads, matching CubeBLEManager.eventRollSettled / eventDoubleTap.
const uint8_t EVENT_ROLL_SETTLED = 0x01;
const uint8_t EVENT_DOUBLE_TAP   = 0x02;

// Keep the advertised name short. A 128-bit service UUID eats 18 of the 31
// advertising bytes, and both apps scan by service UUID, so the name is
// cosmetic — a longer one risks overflowing the packet and going invisible.
#define DEVICE_NAME "Cube"

const int MPU_ADDR = 0x68;
int16_t ax, ay, az;

// --- Tap detection tuning (unchanged from the standalone sketch) ---
const float TAP_THRESHOLD_G = 1.8;              // total accel magnitude spike above this = one tap edge
const unsigned long TAP_DEBOUNCE_MS = 150;      // ignore retriggers within this window
const unsigned long DOUBLE_TAP_WINDOW_MS = 400; // max gap between two taps to count as a double-tap
unsigned long lastTapEdgeTime = 0;
bool waitingForSecondTap = false;
unsigned long firstTapTime = 0;

// A tumbling cube throws magnitude spikes well past TAP_THRESHOLD_G, which
// would otherwise report a mid-roll tumble as a drink tap. Require the cube to
// have been sitting still just before a spike for it to count as a real tap.
const unsigned long TAP_REQUIRE_REST_MS = 120;

// --- Motion / roll detection ---
const float REST_BAND_G = 0.15;        // |mag - 1g| below this = sitting still
const float ROLL_MOTION_G = 0.35;      // |mag - 1g| above this = being moved
const unsigned long MOTION_GAP_MS = 120;      // gap this long splits one motion burst from the next
const unsigned long ROLL_MIN_MOTION_MS = 250; // continuous motion needed to count as a roll, not a tap
const unsigned long ROLL_SETTLE_MS = 500;     // stillness needed after motion before calling it settled

bool inMotion = false;
unsigned long motionStart = 0;
unsigned long lastMotionAt = 0;
unsigned long quietSince = 0;          // when the cube last entered the rest band (0 = not at rest)

// --- Face reporting ---
const unsigned long FACE_STABLE_MS = 400;  // hold a face this long before notifying a change
int8_t candidateFace = -1;
unsigned long candidateSince = 0;
int8_t notifiedFace = -1;                  // last face index pushed to the app

// --- LED ---
// No RGB LED is wired to the cube yet, so colours are approximated with blink
// patterns on the dev board's onboard LED. Swap applyLED() for NeoPixel writes
// when the real LED lands — nothing else needs to change.
const int LED_PIN = 2;
uint8_t ledCommand = 0;                    // last LEDCommand byte received
unsigned long ledPhaseStart = 0;
bool ledOn = false;

BLECharacteristic *faceCharacteristic;
BLECharacteristic *eventCharacteristic;
bool deviceConnected = false;

// ---------------------------------------------------------------- MPU6050

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

// The apps speak face index 0-5, not pips. Mode.allCases is ordered
// deepWork, move, create, social, rest, admin/hydrate — and Mode.pipCount is
// faceIndex + 1 in both apps, so pips map straight down by one.
uint8_t faceIndexFromPips(int pips) {
  return (uint8_t)(pips - 1);
}

// ---------------------------------------------------------------- BLE

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    deviceConnected = true;
    Serial.println("BLE: app connected");
  }
  void onDisconnect(BLEServer *server) override {
    deviceConnected = false;
    Serial.println("BLE: app disconnected, advertising again");
    server->getAdvertising()->start();
  }
};

class LEDCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue();
    if (value.length() < 1) return;
    ledCommand = (uint8_t)value[0];
    ledPhaseStart = millis();
    Serial.print("LED command: ");
    Serial.println(ledCommand);
  }
};

void notifyFace(uint8_t faceIndex) {
  notifiedFace = (int8_t)faceIndex;
  faceCharacteristic->setValue(&faceIndex, 1);   // also serves the app's initial read
  if (deviceConnected) faceCharacteristic->notify();

  Serial.print("Face index -> ");
  Serial.println(faceIndex);
}

void notifyEvent(uint8_t event) {
  eventCharacteristic->setValue(&event, 1);
  if (deviceConnected) eventCharacteristic->notify();

  Serial.println(event == EVENT_DOUBLE_TAP ? "Event -> DOUBLE TAP" : "Event -> ROLL SETTLED");
}

// ---------------------------------------------------------------- LED

// onMs/offMs per LEDCommand: off, red, yellow, green, partyPulse, celebrate.
// Colour isn't expressible on a single onboard LED, so each state gets a
// distinguishable rhythm instead.
const unsigned long LED_PATTERNS[6][2] = {
  {0, 1000},      // 0 off        — dark
  {1400, 600},    // 1 red        — long on, brief blink off
  {500, 500},     // 2 yellow     — even blink
  {120, 1880},    // 3 green      — brief heartbeat
  {90, 90},       // 4 partyPulse — fast strobe
  {60, 60},       // 5 celebrate  — faster strobe
};

void applyLED(unsigned long now) {
  uint8_t cmd = ledCommand < 6 ? ledCommand : 0;
  unsigned long onMs = LED_PATTERNS[cmd][0];
  unsigned long offMs = LED_PATTERNS[cmd][1];

  if (onMs == 0) {
    if (ledOn) { ledOn = false; digitalWrite(LED_PIN, LOW); }
    return;
  }

  unsigned long elapsed = now - ledPhaseStart;
  if (ledOn && elapsed >= onMs) {
    ledOn = false;
    ledPhaseStart = now;
    digitalWrite(LED_PIN, LOW);
  } else if (!ledOn && elapsed >= offMs) {
    ledOn = true;
    ledPhaseStart = now;
    digitalWrite(LED_PIN, HIGH);
  }
}

// ---------------------------------------------------------------- setup

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Wire.begin(21, 22);
  mpuWrite(0x6B, 0x00); // wake MPU6050
  delay(100);

  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  faceCharacteristic = service->createCharacteristic(
    FACE_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  faceCharacteristic->addDescriptor(new BLE2902());

  eventCharacteristic = service->createCharacteristic(
    EVENT_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  eventCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *ledCharacteristic = service->createCharacteristic(
    LED_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  ledCharacteristic->setCallbacks(new LEDCallbacks());

  uint8_t initialFace = 0;
  faceCharacteristic->setValue(&initialFace, 1);
  service->start();

  // Both apps scan with scanForPeripherals(withServices:), so the service UUID
  // has to be in the advertising packet or they'll never see the cube.
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("Cube advertising over BLE");
}

// ---------------------------------------------------------------- loop

void loop() {
  readAccel();

  float gx = ax / 16384.0; // g
  float gy = ay / 16384.0;
  float gz = az / 16384.0;
  float mag = sqrt(gx * gx + gy * gy + gz * gz);
  float dev = fabs(mag - 1.0);   // how far from resting gravity

  unsigned long now = millis();

  // How long the cube had been still *before* this sample. Read it before the
  // motion state below consumes it, so a tap spike is judged on the quiet that
  // preceded it rather than on the spike itself.
  unsigned long quietFor = (quietSince == 0) ? 0 : (now - quietSince);

  // --- Tap detection: sharp spike, from rest, debounced ---
  if (mag > TAP_THRESHOLD_G && (now - lastTapEdgeTime) > TAP_DEBOUNCE_MS
      && quietFor >= TAP_REQUIRE_REST_MS) {
    lastTapEdgeTime = now;

    if (waitingForSecondTap && (now - firstTapTime) < DOUBLE_TAP_WINDOW_MS) {
      Serial.println(">>> DOUBLE TAP <<<");
      notifyEvent(EVENT_DOUBLE_TAP);
      waitingForSecondTap = false; // consumed, don't let a 3rd tap chain onto this
    } else {
      waitingForSecondTap = true;
      firstTapTime = now;
    }
  }

  // A first tap with no partner inside the window was just a single tap. The
  // apps don't consume single taps today, so this only goes to serial.
  if (waitingForSecondTap && (now - firstTapTime) > DOUBLE_TAP_WINDOW_MS) {
    waitingForSecondTap = false;
    Serial.println(">>> single tap <<<");
  }

  // --- Motion tracking ---
  if (dev > ROLL_MOTION_G) {
    // A long enough gap means this is a fresh burst, not a continuation. That
    // is what separates a rolled cube (continuous) from taps (isolated spikes,
    // at least TAP_DEBOUNCE_MS apart).
    if (!inMotion || (now - lastMotionAt) > MOTION_GAP_MS) motionStart = now;
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
    } else if (face != notifiedFace && (now - candidateSince) > FACE_STABLE_MS) {
      notifyFace((uint8_t)face);
    }
  }

  // --- Roll settled ---
  // Fires only after sustained motion followed by stillness, so setting the
  // cube down gently or tapping it doesn't read as a roll.
  if (inMotion && settled) {
    unsigned long motionDuration = lastMotionAt - motionStart;
    inMotion = false;

    if (motionDuration >= ROLL_MIN_MOTION_MS) {
      // The app's roll handler reads the *current* face when the event carries
      // none, so push the landed face first if it hasn't gone out yet.
      int8_t face = (int8_t)faceIndexFromPips(faceFromAccel(gx, gy, gz));
      if (face != notifiedFace) notifyFace((uint8_t)face);
      notifyEvent(EVENT_ROLL_SETTLED);
    }
  }

  applyLED(now);

  delay(5); // fast sampling so short taps aren't missed
}
