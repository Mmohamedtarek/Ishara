// BLE link to the app. Implements docs/BLE-CONTRACT.md (repo root) v1: the Ishara GATT
// service, binary DATA frames, text commands on CMD and "#" lines on EVENT.
// NimBLE runs in its own task: commands and link changes are queued and handled in
// bleLoop(), so everything else (sensors, calibration, NVS) stays on the Arduino loop task.
// With BLE_ENABLED=0 (Wokwi build) every function is a no-op.
#pragma once
#include <Arduino.h>
#include "sensors.h"

void bleBegin();                                // start advertising as "Ishara-XXXX"
void bleLoop();                                 // every loop(): link changes + commands
void bleSample(const Sample& s, uint16_t seq);  // every 20 ms sample: DATA frames when streaming
const char* bleName();                          // advertised name, or "off"

// One EVENT line (the "\n" is added; split across notifications if needed). Dropped when
// no app is connected.
void bleEvent(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
