#include "sensors.h"
#include <Wire.h>
#include <math.h>

static bool g_imuOk = false;
static float g_gyroBias[3] = {0, 0, 0};
static float g_roll = 0;
static bool g_rollInit = false;

static bool mpuWrite(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  return Wire.endTransmission() == 0;
}

bool imuProbe() {
  Wire.beginTransmission(MPU_ADDR);
  g_imuOk = (Wire.endTransmission() == 0);
  if (g_imuOk) {
    // Wake up, gyro +-500 deg/s, accel +-4 g.
    g_imuOk = mpuWrite(MPU_REG_PWR_MGMT_1, 0x00) &&
              mpuWrite(MPU_REG_GYRO_CONFIG, MPU_GYRO_500DPS) &&
              mpuWrite(MPU_REG_ACCEL_CONFIG, MPU_ACCEL_4G);
  }
  g_rollInit = false;
  return g_imuOk;
}

bool imuPresent() { return g_imuOk; }

void sensorsBegin() {
  analogReadResolution(12);
  for (uint8_t i = 0; i < NUM_FINGERS; i++) analogSetPinAttenuation(FLEX_PINS[i], ADC_11db);
  analogSetPinAttenuation(PIN_BATTERY, ADC_11db);
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQ_HZ);
  imuProbe();
}

void sensorsSetGyroBias(const float bias[3]) {
  for (int i = 0; i < 3; i++) g_gyroBias[i] = bias[i];
}

float accelRollDeg(float ax, float ay, float az) {
  (void)ax;
  return atan2f(ay, az) * 180.0f / PI;
}

static bool readImu(int16_t accel[3], int16_t gyro[3]) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_REG_ACCEL_XOUT_H);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((int)MPU_ADDR, 14) != 14) return false;
  uint8_t b[14];
  for (int i = 0; i < 14; i++) b[i] = Wire.read();
  for (int i = 0; i < 3; i++) {
    accel[i] = (int16_t)((b[i * 2] << 8) | b[i * 2 + 1]);
    gyro[i] = (int16_t)((b[8 + i * 2] << 8) | b[9 + i * 2]);  // skip temp at 6..7
  }
  return true;
}

void sensorsRead(Sample& s) {
  for (uint8_t f = 0; f < NUM_FINGERS; f++) {
    uint32_t sum = 0;
    for (uint8_t k = 0; k < FLEX_OVERSAMPLE; k++) sum += analogRead(FLEX_PINS[f]);
    s.flex[f] = sum / FLEX_OVERSAMPLE;
  }

  if (!(g_imuOk && readImu(s.accel, s.gyro))) {
    for (int i = 0; i < 3; i++) s.accel[i] = s.gyro[i] = 0;
  }

  // Complementary filter: gyro for fast motion, accel to stop drift.
  float accRoll = accelRollDeg(s.accel[0], s.accel[1], s.accel[2]);
  float rate = (s.gyro[ROLL_GYRO_AXIS] - g_gyroBias[ROLL_GYRO_AXIS]) / GYRO_LSB_PER_DPS;
  if (!g_rollInit) {
    g_roll = accRoll;
    g_rollInit = true;
  } else {
    float predicted = g_roll + rate * (SAMPLE_PERIOD_MS / 1000.0f);
    // Keep the blend continuous across the +-180 wrap.
    float diff = accRoll - predicted;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    g_roll = predicted + (1.0f - ROLL_FILTER_ALPHA) * diff;
    if (g_roll > 180) g_roll -= 360;
    if (g_roll < -180) g_roll += 360;
  }
  s.rollDeg = g_roll;
}

static uint8_t batteryPercent(uint16_t mv) {
  if (mv <= BAT_EMPTY_MV) return 0;
  if (mv >= BAT_FULL_MV) return 100;
  return (uint8_t)((uint32_t)(mv - BAT_EMPTY_MV) * 100 / (BAT_FULL_MV - BAT_EMPTY_MV));
}

Battery batteryRead() {
  uint32_t mvSum = 0, rawSum = 0;
  for (uint8_t k = 0; k < BAT_OVERSAMPLE; k++) {
    mvSum += analogReadMilliVolts(PIN_BATTERY);
    rawSum += analogRead(PIN_BATTERY);
  }
  uint32_t pinMv = mvSum / BAT_OVERSAMPLE;
  uint32_t scaledMv = (rawSum / BAT_OVERSAMPLE) * ADC_REF_MV / ADC_MAX;
  // Trust the calibrated reading unless it is impossible or far from the raw one.
  uint32_t diff = pinMv > scaledMv ? pinMv - scaledMv : scaledMv - pinMv;
  Battery b;
  b.fallback = pinMv > ADC_REF_MV || diff > BAT_SANITY_TOL_MV;
  b.mv = (uint16_t)((b.fallback ? scaledMv : pinMv) * BAT_DIVIDER_RATIO);
  b.pct = batteryPercent(b.mv);
  return b;
}

const char* batterySource(const Battery& b) {
  return b.fallback ? "analogRead scaled to 3.3 V (fallback)" : "analogReadMilliVolts";
}

static const uint8_t BAT_LOW_READINGS = BAT_LOW_DEBOUNCE_MS / BAT_CHECK_MS;
static BatState g_batState = BatState::Unknown;
static Battery g_batLast = {0, 0, false};
static uint8_t g_lowCount = 0;  // consecutive readings in the LOW band

bool batteryUpdate() {
  g_batLast = batteryRead();
  uint16_t mv = g_batLast.mv;
  BatState next = g_batState;
  if (mv < BAT_NONE_MV) {
    // A Li-Po's protection cuts off long before 2.5 V, so this is USB power: switch at once.
    g_lowCount = 0;
    next = BatState::NoBattery;
  } else if (mv <= BAT_LOW_MV) {
    // Enter LOW only after BAT_LOW_DEBOUNCE_MS of consecutive LOW readings.
    if (g_batState != BatState::Low && ++g_lowCount >= BAT_LOW_READINGS) next = BatState::Low;
  } else {
    g_lowCount = 0;
    if (g_batState != BatState::Low || mv > BAT_LOW_MV + BAT_LOW_HYST_MV) next = BatState::Ok;
  }
  bool changed = next != g_batState;
  g_batState = next;
  return changed;
}

BatState batteryState() { return g_batState; }

const Battery& batteryLast() { return g_batLast; }
