// Ishara Glove: every sensor pin and tunable constant lives here, shared by all boards.
// Board-specific settings (status LED, board name) live in board.h.
#pragma once
#include <Arduino.h>

// ---------- Build ----------
static const char* const FW_VERSION = "0.2.0";

// Set per PlatformIO environment (see platformio.ini). Defaults = hardware behaviour.
#ifndef STREAM_ON_BOOT
#define STREAM_ON_BOOT 1  // raw 12-field stream on at boot (record.py / live.py expect it)
#endif
#ifndef SIM_MODE
#define SIM_MODE 0        // 1 = Wokwi simulation build (only changes the boot banner)
#endif

// ---------- Pins (GPIO numbers) ----------
// Same GPIOs on every board (DevKitC-1 and XIAO ESP32-S3), never per board: the AI models,
// Python tools and app must not depend on which board is inside.
// All analog inputs are on ADC1 (ESP32-S3 GPIO 1-10 = ADC1_CH0-9). ADC2 is shared with the
// radio driver, ADC1 is not, so these readings keep working while Wi-Fi / BLE is on.
//   GPIO  1  2  3  4  7  (flex)   8 (battery)  ->  ADC1_CH0 CH1 CH2 CH3 CH6   CH7
static const uint8_t NUM_FINGERS = 5;
static constexpr uint8_t FLEX_PINS[NUM_FINGERS] = {1, 2, 3, 4, 7};  // thumb, index, middle, ring, pinky
static const char* const FINGER_NAMES[NUM_FINGERS] = {"Thumb", "Index", "Middle", "Ring", "Pinky"};

static const uint8_t PIN_I2C_SDA = 5;
static const uint8_t PIN_I2C_SCL = 6;
static const uint32_t I2C_FREQ_HZ = 400000;

static const uint8_t PIN_BATTERY = 8;  // midpoint of a 220k/220k divider

// The pin table above is fixed for all boards. If one of these fails, a pin was changed
// (maybe inside a BOARD_* #if): change the wiring of BOTH boards and the README table instead.
static_assert(FLEX_PINS[0] == 1 && FLEX_PINS[1] == 2 && FLEX_PINS[2] == 3 &&
                  FLEX_PINS[3] == 4 && FLEX_PINS[4] == 7,
              "flex GPIOs must be 1,2,3,4,7 on every board");
static_assert(PIN_I2C_SDA == 5 && PIN_I2C_SCL == 6, "MPU-6050 I2C must be SDA 5 / SCL 6 on every board");
static_assert(PIN_BATTERY == 8, "battery sense must be GPIO8 on every board");
static constexpr bool isAdc1Pin(uint8_t gpio) { return gpio >= 1 && gpio <= 10; }
static_assert(isAdc1Pin(FLEX_PINS[0]) && isAdc1Pin(FLEX_PINS[1]) && isAdc1Pin(FLEX_PINS[2]) &&
                  isAdc1Pin(FLEX_PINS[3]) && isAdc1Pin(FLEX_PINS[4]) && isAdc1Pin(PIN_BATTERY),
              "analog inputs must be on ADC1 (GPIO 1-10) so they work while the radio is on");

// ---------- Serial ----------
static const uint32_t SERIAL_BAUD = 115200;
static const uint32_t STATUS_PERIOD_MS = 1000;  // "#" status line while no stream is on

// ---------- Sampling ----------
static const uint32_t SAMPLE_PERIOD_MS = 20;  // 50 Hz
static const uint8_t FLEX_OVERSAMPLE = 8;      // reads averaged per flex value
static const uint16_t ADC_MAX = 4095;          // 12-bit

// ---------- MPU-6050 ----------
static const uint8_t MPU_ADDR = 0x68;          // AD0 to GND
static const uint8_t MPU_REG_PWR_MGMT_1 = 0x6B;
static const uint8_t MPU_REG_GYRO_CONFIG = 0x1B;
static const uint8_t MPU_REG_ACCEL_CONFIG = 0x1C;
static const uint8_t MPU_REG_ACCEL_XOUT_H = 0x3B;  // 14 bytes: accel, temp, gyro
static const uint8_t MPU_GYRO_500DPS = 0x08;
static const uint8_t MPU_ACCEL_4G = 0x08;
static const float ACCEL_LSB_PER_G = 8192.0f;   // at +-4 g
static const float GYRO_LSB_PER_DPS = 65.5f;    // at +-500 deg/s

// Roll = rotation about the forearm axis. With the MPU flat on the back of the hand,
// accel roll is atan2(ay, az) and the matching gyro axis is X (0=x, 1=y, 2=z).
static const uint8_t ROLL_GYRO_AXIS = 0;
static const float ROLL_FILTER_ALPHA = 0.98f;   // complementary filter: gyro weight

// ---------- Calibration ----------
static const uint32_t CAL_COUNTDOWN_MS = 3000;  // 3-2-1
static const uint32_t CAL_OPEN_MS = 2000;     // also measures gyro bias + neutral roll
static const uint32_t CAL_FIST_MS = 2000;
static const uint32_t CAL_ROTATE_MS = 4000;
static const uint32_t CAL_BAR_PERIOD_MS = 500;  // live progress bar refresh
static const uint16_t CAL_MAX_SAMPLES = CAL_ROTATE_MS / SAMPLE_PERIOD_MS;  // longest window

static const uint16_t CAL_MIN_FLEX_RANGE = 300;  // |fist - open| below this = warning
static const float CAL_MIN_ROLL_RANGE_DEG = 30.0f;

// Stillness check for the open-hand step (it doubles as the gyro bias measurement).
// At +-500 deg/s one LSB is 1/65.5 = 0.015 deg/s. The MPU-6050's own noise is about
// 0.1 deg/s rms (~7 LSB) and a hand held still in the air adds roughly 0.5-1.5 deg/s of
// tremor, while any deliberate movement is well above 10 deg/s. 3 deg/s (~200 LSB) sits
// between the two: a normal steady hand passes, a hand that moved gets the warning.
static const float CAL_STILL_GYRO_STD_DPS = 3.0f;  // per-axis gyro std dev limit

// ---------- Storage (NVS) ----------
static const char* const NVS_NAMESPACE = "ishara";
static const uint16_t CAL_VERSION = 2;         // written on save; bump when the saved data changes
static const uint16_t CAL_VERSION_OLDEST = 1;  // oldest version still loaded (v1 has the same fields)

// ---------- Battery ----------
static const float BAT_DIVIDER_RATIO = 2.0f;  // 220k/220k halves the voltage
static const uint16_t BAT_EMPTY_MV = 3300;    // 0 %
static const uint16_t BAT_FULL_MV = 4150;     // 100 %
static const uint32_t BAT_REPORT_MS = 10000;  // "# BAT" line while a stream is on
static const uint8_t BAT_OVERSAMPLE = 16;     // ADC reads averaged per battery reading
// Battery state (printed as "#BAT ..." at boot and on every change).
static const uint16_t BAT_NONE_MV = 2500;     // below: no battery, running from USB (never sleep)
static const uint16_t BAT_LOW_MV = 3400;      // BAT_NONE_MV..this: LOW, above: OK
static const uint16_t BAT_LOW_HYST_MV = 100;  // leave LOW only above BAT_LOW_MV + this
static const uint32_t BAT_LOW_DEBOUNCE_MS = 5000;  // LOW must hold this long before it is entered
static const uint32_t BAT_CHECK_MS = 500;     // battery state update period
static const uint16_t ADC_REF_MV = 3300;      // fallback: analogRead() scaled to 3.3 V
// analogReadMilliVolts() is "nonsense" if it is above ADC_REF_MV or further than this
// from the scaled raw reading (the simulator may not model the eFuse ADC calibration).
static const uint16_t BAT_SANITY_TOL_MV = 250;
