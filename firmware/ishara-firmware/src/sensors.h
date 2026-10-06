// Flex sensor, MPU-6050 and battery reading.
#pragma once
#include <Arduino.h>
#include "config.h"

struct Sample {
  uint16_t flex[NUM_FINGERS];  // raw ADC 0..4095, average of FLEX_OVERSAMPLE reads
  int16_t accel[3];            // raw, +-4 g
  int16_t gyro[3];             // raw, +-500 deg/s
  float rollDeg;               // filtered roll (accel + gyro), absolute
};

void sensorsBegin();
bool imuPresent();              // true if the MPU-6050 answered on I2C
bool imuProbe();                // re-check the bus and re-init if found
void sensorsRead(Sample& s);    // call once per 20 ms tick

// Gyro bias (raw counts) subtracted before the roll filter integrates.
void sensorsSetGyroBias(const float bias[3]);

float accelRollDeg(float ax, float ay, float az);
struct Battery {
  uint16_t mv;      // battery voltage (after undoing the divider)
  uint8_t pct;      // 0..100 between BAT_EMPTY_MV and BAT_FULL_MV
  bool fallback;    // true: analogRead() scaled to 3.3 V, false: analogReadMilliVolts()
};
Battery batteryRead();
const char* batterySource(const Battery& b);  // method name, for banner / report

// Battery state from the measured battery voltage (thresholds in config.h).
// Any low-battery action (warning, deep sleep) must check for Low only: NoBattery means
// USB power with nothing on the divider and must never sleep or shut down.
enum class BatState : uint8_t { Unknown, NoBattery, Low, Ok };  // Unknown: boot, not decided yet
bool batteryUpdate();          // call every BAT_CHECK_MS; true if the state changed
BatState batteryState();
const Battery& batteryLast();  // the reading from the last batteryUpdate()
// "#BAT NO_BATTERY (USB)" / "#BAT LOW 3.38V" / "#BAT OK 3.92V 78%" for a state and the last
// reading (no line end). Unknown gives an empty string.
void batteryStateLine(BatState st, char* buf, size_t len);
