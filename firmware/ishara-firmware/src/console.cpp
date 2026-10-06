#include "console.h"
#include <stdarg.h>

void say(const char* fmt, ...) {
  char buf[256];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  Serial.print("# ");
  Serial.print(buf);
  Serial.print(EOL);
}

void sayBlank() { Serial.print("#" EOL); }
