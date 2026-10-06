// Serial text output. Every line the firmware prints ends with CRLF so it looks right in
// any terminal. Human-readable lines start with "# " so the CSV tools skip them.
#pragma once
#include <Arduino.h>

#define EOL "\r\n"

void say(const char* fmt, ...) __attribute__((format(printf, 1, 2)));  // "# " + text + CRLF
void sayBlank();                                                        // "#" + CRLF
