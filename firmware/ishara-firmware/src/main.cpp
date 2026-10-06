// Ishara Glove firmware: calibration stage.
// Raw stream:        seq,f0,f1,f2,f3,f4,ax,ay,az,gx,gy,gz   (12 fields, 50 Hz)
// Normalized stream: N,f0,f1,f2,f3,f4,roll,gx,gy,gz         (10 fields)
// Everything else starts with '#' so record.py / live.py ignore it. All lines end with CRLF.
#include <Arduino.h>
#include "board.h"
#include "config.h"
#include "console.h"
#include "sensors.h"
#include "calibration.h"

static bool g_rawOn = STREAM_ON_BOOT;
static bool g_normOn = false;
static uint8_t g_seq = 0;
static uint32_t g_nextSample = 0;
static uint32_t g_lastBat = 0;
static uint32_t g_lastStatus = 0;
static uint32_t g_nextBatCheck = 0;

static void printHelp() {
  say("Keys:");
  say(" c  start calibration: 1 open hand (2 s) / 2 fist (2 s) / 3 turn the wrist (4 s)");
  say("    y accept step / x redo step / q cancel");
  say(" s  raw 12-field stream on/off");
  say(" n  normalized stream on/off");
  say(" p  print calibration report");
  say(" j  print saved calibration as one #CAL JSON line");
  say(" r  reset calibration");
  say(" h  this help");
  say("With both streams off a '#' status line prints every %lu s.",
      (unsigned long)(STATUS_PERIOD_MS / 1000));
}

static void printBanner() {
  Battery b = batteryRead();
  sayBlank();
  say("========================================");
  say("Ishara Glove - firmware v%s (%s build)", FW_VERSION, SIM_MODE ? "Wokwi simulation" : "hardware");
  say("========================================");
  say("Board        %s", BOARD_NAME);
  say("MPU-6050     %s", imuPresent() ? "OK" : "NOT FOUND");
  if (calValid()) say("Calibration  loaded (format v%u)", calData().version);
  else say("Calibration  NOT CALIBRATED - press c");
  say("Battery      %u%% %u mV (%s)", b.pct, b.mv, batterySource(b));
  say("Raw stream   %s at boot (s toggles)", g_rawOn ? "ON" : "OFF");
  printHelp();
}

static void printBattery() {
  Battery b = batteryRead();
  say("BAT %u%% (%u mV)", b.pct, b.mv);
}

// "#BAT <state> ..." (no commas, so the CSV tools skip it), at boot and on every state change.
static void printBatState() {
  const Battery& b = batteryLast();
  switch (batteryState()) {
    case BatState::NoBattery: Serial.print("#BAT NO_BATTERY (USB)" EOL); break;
    case BatState::Low: Serial.printf("#BAT LOW %.2fV" EOL, b.mv / 1000.0f); break;
    case BatState::Ok: Serial.printf("#BAT OK %.2fV %u%%" EOL, b.mv / 1000.0f, b.pct); break;
    case BatState::Unknown: break;  // boot, LOW debounce still running
  }
}

// One line: battery, calibration state, each finger raw (+ bend %), roll.
static void printStatus(const Sample& s) {
  char line[256];
  size_t n = 0;
  Battery b = batteryRead();
  bool cal = calValid();
  n += snprintf(line + n, sizeof(line) - n, "BAT %u%% %u mV | %s", b.pct, b.mv,
                cal ? "CAL ok" : "NOT CALIBRATED");
  for (uint8_t f = 0; f < NUM_FINGERS && n < sizeof(line); f++) {
    if (cal)
      n += snprintf(line + n, sizeof(line) - n, " | %s %u %3u%%", FINGER_NAMES[f], s.flex[f],
                    (unsigned)lroundf(calFingerNorm(f, s.flex[f]) * 100));
    else
      n += snprintf(line + n, sizeof(line) - n, " | %s %u", FINGER_NAMES[f], s.flex[f]);
  }
  if (n < sizeof(line)) {
    if (!imuPresent())
      snprintf(line + n, sizeof(line) - n, " | roll n/a (no MPU)");
    else if (cal)
      snprintf(line + n, sizeof(line) - n, " | roll %.1f deg (rel %.1f)", s.rollDeg,
               calRollRelDeg(s.rollDeg));
    else
      snprintf(line + n, sizeof(line) - n, " | roll %.1f deg", s.rollDeg);
  }
  say("%s", line);
}

static void handleKey(char k) {
  if (calActive()) {
    if (k == 'c') calStart();  // restart from step 1
    else if (k == 'r') calReset();
    else if (k == 'h') printHelp();
    else calHandleKey(k);
    return;
  }
  switch (k) {
    case 'c': calStart(); break;
    case 's':
      g_rawOn = !g_rawOn;
      say("Raw stream %s", g_rawOn ? "ON" : "OFF");
      break;
    case 'n':
      if (!g_normOn && !calValid()) {
        say("NOT CALIBRATED - press c first");
        break;
      }
      g_normOn = !g_normOn;
      say("Normalized stream %s", g_normOn ? "ON" : "OFF");
      break;
    case 'p': calReport(); break;
    case 'j': calPrintJson(); break;
    case 'r':
      calReset();
      g_normOn = false;
      break;
    case 'h': printHelp(); break;
    default: break;  // ignore newlines and unknown keys
  }
}

static void printRaw(const Sample& s) {
  Serial.printf("%u,%u,%u,%u,%u,%u,%d,%d,%d,%d,%d,%d" EOL, g_seq, s.flex[0], s.flex[1],
                s.flex[2], s.flex[3], s.flex[4], s.accel[0], s.accel[1], s.accel[2], s.gyro[0],
                s.gyro[1], s.gyro[2]);
}

static void printNorm(const Sample& s) {
  const CalData& c = calData();
  Serial.printf("N,%.3f,%.3f,%.3f,%.3f,%.3f,%.1f,%.1f,%.1f,%.1f" EOL, calFingerNorm(0, s.flex[0]),
                calFingerNorm(1, s.flex[1]), calFingerNorm(2, s.flex[2]),
                calFingerNorm(3, s.flex[3]), calFingerNorm(4, s.flex[4]),
                calRollRelDeg(s.rollDeg), (s.gyro[0] - c.gyroBias[0]) / GYRO_LSB_PER_DPS,
                (s.gyro[1] - c.gyroBias[1]) / GYRO_LSB_PER_DPS,
                (s.gyro[2] - c.gyroBias[2]) / GYRO_LSB_PER_DPS);
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  sensorsBegin();
  calBegin();
  printBanner();
  g_nextSample = millis();
  g_lastBat = millis();
  g_lastStatus = millis();
  if (batteryUpdate()) printBatState();  // anything but a LOW reading is decided at once
  g_nextBatCheck = millis() + BAT_CHECK_MS;
}

void loop() {
  while (Serial.available()) handleKey((char)Serial.read());

  uint32_t now = millis();
  if ((int32_t)(now - g_nextSample) < 0) return;  // not time yet
  g_nextSample += SAMPLE_PERIOD_MS;
  if ((int32_t)(now - g_nextSample) > (int32_t)(5 * SAMPLE_PERIOD_MS)) g_nextSample = now;  // fell behind: resync

  Sample s;
  sensorsRead(s);

  if ((int32_t)(now - g_nextBatCheck) >= 0) {
    g_nextBatCheck = now + BAT_CHECK_MS;
    if (batteryUpdate()) printBatState();
  }

  if (calActive()) {
    calTick(s, now);  // streams and status pause during calibration so the prompts stay readable
    g_lastStatus = g_lastBat = now;
  } else if (g_rawOn || g_normOn) {
    if (g_rawOn) printRaw(s);
    if (g_normOn && calValid()) printNorm(s);
    g_lastStatus = now;
    if (now - g_lastBat >= BAT_REPORT_MS) {
      g_lastBat = now;
      printBattery();
    }
  } else if (now - g_lastStatus >= STATUS_PERIOD_MS) {
    g_lastStatus = g_lastBat = now;
    printStatus(s);  // already carries the battery, so no separate BAT line
  }
  g_seq++;
}
