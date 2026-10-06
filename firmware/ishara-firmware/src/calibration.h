// Calibration state machine (mirrors the app's Calibrate screen).
// Non-blocking: call calTick() once per sample and calHandleKey() for each key.
// Two flows write the same saved calibration: the serial wizard (keys) and the app (BLE).
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
const char* calJson();           // the saved calibration as JSON, nullptr if none

// App-driven calibration over BLE (BLE-CONTRACT.md section 7). Replies go out with bleEvent().
// calTick() also runs these steps, so call it on every sample, not only while calActive().
void calBleCommand(const char* arg);  // "OPEN" / "FIST" / "TURN" / "SAVE" / "CANCEL"
void calBleDrop();                    // forget unsaved app steps (disconnect, serial 'c' / 'r')
bool calBleBusy();                    // an app step is capturing now

// Normalized helpers (use the saved calibration).
float calFingerNorm(uint8_t finger, uint16_t raw);  // 0 open .. 1 fist, clamped
float calRollRelDeg(float rollDeg);                 // roll minus neutral, wrapped
