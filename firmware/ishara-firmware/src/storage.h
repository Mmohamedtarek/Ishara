// Calibration data and NVS (Preferences) storage.
#pragma once
#include <Arduino.h>
#include "config.h"

struct CalData {
  uint16_t version;
  uint16_t open[NUM_FINGERS];  // raw ADC, hand open
  uint16_t fist[NUM_FINGERS];  // raw ADC, fist
  float gyroBias[3];           // raw counts
  float gravity[3];            // mean accel during the open-hand step, raw counts
  float rollMin, rollMax;      // degrees, absolute
  float rollNeutral;           // degrees, absolute
};

bool storageLoad(CalData& cal);   // false if missing or version not in CAL_VERSION_OLDEST..CAL_VERSION
bool storageSave(const CalData& cal);
void storageClear();
