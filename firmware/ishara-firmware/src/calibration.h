// Calibration state machine (mirrors the app's Calibrate screen).
// Non-blocking: call calTick() once per sample and calHandleKey() for each key.
#pragma once
#include <Arduino.h>
#include "sensors.h"
#include "storage.h"

void calBegin();                 // load saved calibration from NVS (prints nothing)
void calStart();                 // 'c': start full calibration from step 1
void calCancel();                // abort without saving
bool calActive();                // true while the wizard runs
void calHandleKey(char key);     // y / x / q while active
void calTick(const Sample& s, uint32_t nowMs);

bool calValid();                 // a saved calibration is loaded
const CalData& calData();
void calReset();                 // 'r': clear NVS and RAM
void calReport();                // 'p': full "===== CALIBRATION REPORT =====" block
void calPrintJson();             // 'j': one "#CAL {...}" line with the saved calibration

// Normalized helpers (use the saved calibration).
float calFingerNorm(uint8_t finger, uint16_t raw);  // 0 open .. 1 fist, clamped
float calRollRelDeg(float rollDeg);                 // roll minus neutral, wrapped
