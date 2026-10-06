// Ishara Glove: the only board-specific settings. Chosen by BOARD_DEVKIT or BOARD_XIAO
// (set per PlatformIO environment). Sensor pins are NOT here: they live in config.h and
// are identical on every board.
#pragma once
#include <Arduino.h>

#if defined(BOARD_DEVKIT) && defined(BOARD_XIAO)
#error "Define only one of BOARD_DEVKIT / BOARD_XIAO"
#elif defined(BOARD_DEVKIT)
// ESP32-S3-DevKitC-1 N16R8. The onboard LED is a WS2812 RGB LED (drive it with
// neopixelWrite(), not digitalWrite()). v1.0 boards wire it to GPIO48, v1.1 boards to
// GPIO38 (printed next to the RGB LED / on the back of the board). Change this if ours is v1.1.
static const char* const BOARD_NAME = "devkit";
static constexpr uint8_t STATUS_LED_PIN = 48;
static constexpr bool STATUS_LED_RGB = true;
static constexpr bool STATUS_LED_ACTIVE_LOW = false;  // n/a for the RGB LED
#elif defined(BOARD_XIAO)
// Seeed XIAO ESP32-S3. The orange user LED is a plain LED on GPIO21, lit when the pin is LOW.
static const char* const BOARD_NAME = "xiao";
static constexpr uint8_t STATUS_LED_PIN = 21;
static constexpr bool STATUS_LED_RGB = false;
static constexpr bool STATUS_LED_ACTIVE_LOW = true;
#else
#error "Define BOARD_DEVKIT or BOARD_XIAO (see platformio.ini)"
#endif
