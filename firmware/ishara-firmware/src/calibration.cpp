#include "calibration.h"
#include <algorithm>
#include <math.h>
#include <stdarg.h>
#include "console.h"

// Every text line starts with '#' and avoids commas, so the 12-field CSV tools ignore it.
// The one exception is the '#CAL {json}' line, which still starts with '#'.

enum Step : uint8_t { STEP_OPEN, STEP_FIST, STEP_ROTATE, STEP_COUNT };
enum Phase : uint8_t { PH_IDLE, PH_COUNTDOWN, PH_CAPTURE, PH_REVIEW };

static const char* const STEP_TITLES[STEP_COUNT] = {
    "Step 1 of 3: Open hand", "Step 2 of 3: Make a fist", "Step 3 of 3: Turn the wrist"};
static const char* const STEP_TAGS[STEP_COUNT] = {"Step 1 of 3", "Step 2 of 3", "Step 3 of 3"};
static const char* const STEP_HINTS[STEP_COUNT] = {
    "Spread your fingers and keep them straight. Hold the hand still.",
    "Close all fingers into a tight fist.",
    "Turn palm to the LEFT then palm to the RIGHT."};
static const uint32_t STEP_MS[STEP_COUNT] = {CAL_OPEN_MS, CAL_FIST_MS, CAL_ROTATE_MS};

static CalData g_saved;       // what is in NVS
static bool g_savedValid = false;
static CalData g_work;        // results being built by the wizard

static Phase g_phase = PH_IDLE;
static Step g_step = STEP_OPEN;
static uint32_t g_phaseStart = 0;
static uint32_t g_lastBar = 0;
static int8_t g_lastCount = -1;

// Capture buffers.
static uint16_t g_flexBuf[NUM_FINGERS][CAL_MAX_SAMPLES];
static uint16_t g_n = 0;
static double g_gyroSum[3], g_gyroSq[3], g_accSum[3];
static float g_rollMin, g_rollMax;

// ---------- small helpers ----------

static void printBar(const char* name, uint8_t pct) {
  char bar[11];
  uint8_t filled = (pct + 5) / 10;
  for (uint8_t i = 0; i < 10; i++) bar[i] = i < filled ? '#' : '-';
  bar[10] = 0;
  say("%-6s %s %3u%%", name, bar, pct);
}

static uint16_t median(uint16_t* data, uint16_t n) {
  static uint16_t tmp[CAL_MAX_SAMPLES];
  if (n == 0) return 0;
  memcpy(tmp, data, n * sizeof(uint16_t));
  std::sort(tmp, tmp + n);
  return tmp[n / 2];
}

static float wrap180(float a) {
  while (a > 180) a -= 360;
  while (a < -180) a += 360;
  return a;
}

static int flexRange(const CalData& c, uint8_t f) { return (int)c.fist[f] - (int)c.open[f]; }
static bool flexOk(const CalData& c, uint8_t f) { return abs(flexRange(c, f)) >= CAL_MIN_FLEX_RANGE; }
static bool rollOk(const CalData& c) { return c.rollMax - c.rollMin >= CAL_MIN_ROLL_RANGE_DEG; }

static float dps(float rawCounts) { return rawCounts / GYRO_LSB_PER_DPS; }

// ---------- flow ----------

static void enterStep(Step st, uint32_t now) {
  g_step = st;
  g_phase = PH_COUNTDOWN;
  g_phaseStart = now;
  g_lastCount = -1;
  sayBlank();
  say("=== %s ===", STEP_TITLES[st]);
  say("%s", STEP_HINTS[st]);
}

static void startCapture(uint32_t now) {
  g_phase = PH_CAPTURE;
  g_phaseStart = now;
  g_lastBar = now;
  g_n = 0;
  for (int i = 0; i < 3; i++) g_gyroSum[i] = g_gyroSq[i] = g_accSum[i] = 0;
  g_rollMin = 1000;
  g_rollMax = -1000;
  say("GO - capturing %s...", STEP_TAGS[g_step]);
}

static void checkFingers() {
  for (uint8_t f = 0; f < NUM_FINGERS; f++) {
    if (!flexOk(g_work, f))
      say("WARNING: %s range only %d counts (need %u). Sensor not bending or disconnected?",
          FINGER_NAMES[f], abs(flexRange(g_work, f)), CAL_MIN_FLEX_RANGE);
  }
}

static void warnImu() {
  if (!imuPresent()) say("WARNING: MPU-6050 not found on I2C (check SDA/SCL wiring and address 0x68).");
}

// Turn the captured buffers into results and print them as a small table.
static void finishCapture() {
  g_phase = PH_REVIEW;
  uint16_t n = g_n ? g_n : 1;

  switch (g_step) {
    case STEP_OPEN: {
      // The hand is held still here, so this step also gives the gyro bias and the
      // gravity reference. Neutral roll = roll of the mean accel vector (wrap-safe mean).
      float gyroStd[3];
      bool moved = false;
      for (int i = 0; i < 3; i++) {
        g_work.gyroBias[i] = g_gyroSum[i] / n;
        g_work.gravity[i] = g_accSum[i] / n;
        double var = g_gyroSq[i] / n - (double)g_work.gyroBias[i] * g_work.gyroBias[i];
        gyroStd[i] = sqrt(var > 0 ? var : 0);
        moved |= dps(gyroStd[i]) > CAL_STILL_GYRO_STD_DPS;
      }
      g_work.rollNeutral = accelRollDeg(g_work.gravity[0], g_work.gravity[1], g_work.gravity[2]);
      for (uint8_t f = 0; f < NUM_FINGERS; f++) g_work.open[f] = median(g_flexBuf[f], g_n);
      say("--- %s result: open hand (%u samples) ---", STEP_TAGS[g_step], g_n);
      say("Finger  median");
      for (uint8_t f = 0; f < NUM_FINGERS; f++) say("%-6s  %6u", FINGER_NAMES[f], g_work.open[f]);
      say("Axis  bias deg/s  std deg/s  gravity g");
      for (int i = 0; i < 3; i++)
        say("%c     %11.2f  %9.2f  %9.2f", 'X' + i, dps(g_work.gyroBias[i]), dps(gyroStd[i]),
            g_work.gravity[i] / ACCEL_LSB_PER_G);
      say("Neutral roll %.1f deg", g_work.rollNeutral);
      warnImu();
      if (moved) say("WARN hand moved during open-hand step, gyro bias may be off - press x to redo");
      break;
    }
    case STEP_FIST: {
      for (uint8_t f = 0; f < NUM_FINGERS; f++) g_work.fist[f] = median(g_flexBuf[f], g_n);
      say("--- %s result: fist medians (%u samples) ---", STEP_TAGS[g_step], g_n);
      say("Finger  median   open  range  flag");
      for (uint8_t f = 0; f < NUM_FINGERS; f++)
        say("%-6s  %6u  %5u  %5d  %s", FINGER_NAMES[f], g_work.fist[f], g_work.open[f],
            flexRange(g_work, f), flexOk(g_work, f) ? "ok" : "LOW");
      checkFingers();
      break;
    }
    case STEP_ROTATE: {
      g_work.rollMin = g_rollMin;
      g_work.rollMax = g_rollMax;
      say("--- %s result: wrist roll (%u samples) ---", STEP_TAGS[g_step], g_n);
      say("Roll deg    min  neutral    max  range  flag");
      say("         %6.1f   %6.1f  %6.1f  %5.1f  %s", g_work.rollMin, g_work.rollNeutral,
          g_work.rollMax, g_work.rollMax - g_work.rollMin, rollOk(g_work) ? "ok" : "LOW");
      warnImu();
      if (!rollOk(g_work))
        say("WARNING: rotation range under %.0f deg. Turn the wrist further.",
            CAL_MIN_ROLL_RANGE_DEG);
      break;
    }
    default:
      break;
  }
  say("Press y to accept or x to redo.");
}

static void finishAll() {
  g_work.version = CAL_VERSION;  // always save in the current format
  g_saved = g_work;
  g_savedValid = true;
  g_phase = PH_IDLE;
  sensorsSetGyroBias(g_saved.gyroBias);
  sayBlank();
  if (storageSave(g_saved)) say("CALIBRATION SAVED");
  else say("ERROR: could not save calibration to NVS");
  calReport();
}

// ---------- public API ----------

void calBegin() {
  g_savedValid = storageLoad(g_saved);
  if (g_savedValid) sensorsSetGyroBias(g_saved.gyroBias);
}

bool calActive() { return g_phase != PH_IDLE; }
bool calValid() { return g_savedValid; }
const CalData& calData() { return g_saved; }

void calStart() {
  memset(&g_work, 0, sizeof(g_work));
  // Measure the new bias without the old one applied.
  const float zero[3] = {0, 0, 0};
  sensorsSetGyroBias(zero);
  sayBlank();
  say("CALIBRATION START (q to cancel)");
  imuProbe();
  warnImu();
  enterStep(STEP_OPEN, millis());
}

void calCancel() {
  if (!calActive()) return;
  g_phase = PH_IDLE;
  if (g_savedValid) sensorsSetGyroBias(g_saved.gyroBias);
  say("Calibration cancelled. Previous calibration kept.");
}

void calHandleKey(char key) {
  if (!calActive()) return;
  if (key == 'q') {
    calCancel();
    return;
  }
  if (g_phase != PH_REVIEW) return;  // y/x only mean something after a capture
  if (key == 'x') {
    say("Redo.");
    enterStep(g_step, millis());
  } else if (key == 'y') {
    if (g_step == STEP_OPEN) sensorsSetGyroBias(g_work.gyroBias);  // use new bias for rotation
    if (g_step + 1 < STEP_COUNT) enterStep((Step)(g_step + 1), millis());
    else finishAll();
  }
}

void calTick(const Sample& s, uint32_t now) {
  uint32_t el = now - g_phaseStart;

  if (g_phase == PH_COUNTDOWN) {
    int8_t count = 3 - el / 1000;  // 3, 2, 1
    if (el >= CAL_COUNTDOWN_MS) {
      startCapture(now);
    } else if (count != g_lastCount) {
      g_lastCount = count;
      say("%d...", count);
    }
    return;
  }
  if (g_phase != PH_CAPTURE) return;

  // Collect this sample.
  if (g_n < CAL_MAX_SAMPLES) {
    for (uint8_t f = 0; f < NUM_FINGERS; f++) g_flexBuf[f][g_n] = s.flex[f];
    g_n++;
  }
  for (int i = 0; i < 3; i++) {
    g_gyroSum[i] += s.gyro[i];
    g_gyroSq[i] += (double)s.gyro[i] * s.gyro[i];
    g_accSum[i] += s.accel[i];
  }
  g_rollMin = min(g_rollMin, s.rollDeg);
  g_rollMax = max(g_rollMax, s.rollDeg);

  // Live progress, like the app screen.
  if (now - g_lastBar >= CAL_BAR_PERIOD_MS) {
    g_lastBar = now;
    uint8_t pct = min<uint32_t>(100, el * 100 / STEP_MS[g_step]);
    printBar("Time", pct);
    if (g_step == STEP_ROTATE) {
      say("Roll %.1f deg  (min %.1f  max %.1f)", s.rollDeg, g_rollMin, g_rollMax);
    } else {
      for (uint8_t f = 0; f < NUM_FINGERS; f++)
        printBar(FINGER_NAMES[f], (uint32_t)s.flex[f] * 100 / ADC_MAX);
      if (g_step == STEP_OPEN)  // bias is being measured: show that the hand is still
        say("Gyro (deg/s) x %.1f  y %.1f  z %.1f", dps(s.gyro[0]), dps(s.gyro[1]), dps(s.gyro[2]));
    }
  }

  if (el >= STEP_MS[g_step]) finishCapture();
}

void calReset() {
  calCancel();
  storageClear();
  memset(&g_saved, 0, sizeof(g_saved));
  g_savedValid = false;
  const float zero[3] = {0, 0, 0};
  sensorsSetGyroBias(zero);
  say("Calibration reset. NOT CALIBRATED");
}

void calReport() {
  uint32_t up = millis() / 1000;
  Battery b = batteryRead();
  sayBlank();
  say("===== CALIBRATION REPORT =====");
  say("Firmware %s  uptime %lu:%02lu:%02lu", FW_VERSION, (unsigned long)(up / 3600),
      (unsigned long)(up / 60 % 60), (unsigned long)(up % 60));
  say("Battery %u%% (%u mV via %s)", b.pct, b.mv, batterySource(b));
  say("MPU-6050 %s", imuPresent() ? "OK" : "NOT FOUND");
  if (!g_savedValid) {
    say("NOT CALIBRATED - press c to calibrate");
  } else {
    if (g_saved.version < CAL_VERSION) say("Calibration format v%u (loaded)", g_saved.version);
    else say("Calibration format v%u", g_saved.version);
    say("Steps 1+2  finger medians (raw ADC)");
    say("Finger    open   fist  range  flag");
    bool anyLow = false;
    for (uint8_t f = 0; f < NUM_FINGERS; f++) {
      anyLow |= !flexOk(g_saved, f);
      say("%-6s  %6u %6u  %5d  %s", FINGER_NAMES[f], g_saved.open[f], g_saved.fist[f],
          flexRange(g_saved, f), flexOk(g_saved, f) ? "ok" : "LOW");
    }
    if (anyLow) say("LOW = |range| under %u counts: sensor not bending or disconnected?", CAL_MIN_FLEX_RANGE);
    say("Step 1    gyro bias deg/s  x %.2f  y %.2f  z %.2f", dps(g_saved.gyroBias[0]),
        dps(g_saved.gyroBias[1]), dps(g_saved.gyroBias[2]));
    say("Step 1    neutral roll %.1f deg", g_saved.rollNeutral);
    say("Step 3    roll deg  min %.1f  max %.1f  range %.1f  %s", g_saved.rollMin,
        g_saved.rollMax, g_saved.rollMax - g_saved.rollMin, rollOk(g_saved) ? "ok" : "LOW");
  }
  say("===== END REPORT =====");
}

// Appends printf output to a fixed buffer, keeping it NUL-terminated.
struct JsonBuf {
  char s[512];
  size_t n = 0;
  void add(const char* fmt, ...) __attribute__((format(printf, 2, 3))) {
    if (n >= sizeof(s)) return;
    va_list ap;
    va_start(ap, fmt);
    int w = vsnprintf(s + n, sizeof(s) - n, fmt, ap);
    va_end(ap);
    if (w > 0) n = min(sizeof(s), n + (size_t)w);
  }
  void num(float v) {  // JSON has no NaN / Infinity
    if (isfinite(v)) add("%.2f", v);
    else add("null");
  }
  void u16s(const char* key, const uint16_t* v) {
    add("\"%s\":[", key);
    for (uint8_t i = 0; i < NUM_FINGERS; i++) add(i ? ",%u" : "%u", v[i]);
    add("]");
  }
  void f3(const char* key, const float* v) {
    add("\"%s\":[", key);
    for (int i = 0; i < 3; i++) {
      if (i) add(",");
      num(v[i]);
    }
    add("]");
  }
};

void calPrintJson() {
  if (!g_savedValid) {
    say("NOT CALIBRATED");
    return;
  }
  // Flex values are raw ADC medians; gyro_bias_raw is raw gyro counts (same units as the
  // stream, GYRO_LSB_PER_DPS counts = 1 deg/s); roll values are degrees.
  // Finger order: thumb index middle ring pinky. "v" is this JSON format's version.
  static JsonBuf j;
  j.n = 0;
  j.add("{\"v\":2,");
  j.u16s("open", g_saved.open);
  j.add(",");
  j.u16s("fist", g_saved.fist);
  j.add(",");
  j.f3("gyro_bias_raw", g_saved.gyroBias);
  j.add(",\"roll_neutral\":");
  j.num(g_saved.rollNeutral);
  j.add(",\"roll_min\":");
  j.num(g_saved.rollMin);
  j.add(",\"roll_max\":");
  j.num(g_saved.rollMax);
  j.add("}");
  Serial.print("#CAL ");
  Serial.print(j.s);
  Serial.print(EOL);
}

float calFingerNorm(uint8_t f, uint16_t raw) {
  int span = flexRange(g_saved, f);  // sign handles either direction
  if (span == 0) return 0;
  float v = ((int)raw - (int)g_saved.open[f]) / (float)span;
  return constrain(v, 0.0f, 1.0f);
}

float calRollRelDeg(float rollDeg) { return wrap180(rollDeg - g_saved.rollNeutral); }
