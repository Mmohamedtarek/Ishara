#include "storage.h"
#include <Preferences.h>

static Preferences prefs;

bool storageLoad(CalData& cal) {
  if (!prefs.begin(NVS_NAMESPACE, true)) return false;  // read-only
  // Older versions with the same CalData layout load as-is; cal.version keeps the saved one.
  uint16_t ver = prefs.getUShort("ver", 0);
  bool ok = ver >= CAL_VERSION_OLDEST && ver <= CAL_VERSION &&
            prefs.getBytesLength("cal") == sizeof(CalData) &&
            prefs.getBytes("cal", &cal, sizeof(CalData)) == sizeof(CalData) &&
            cal.version == ver;
  prefs.end();
  return ok;
}

bool storageSave(const CalData& cal) {
  if (!prefs.begin(NVS_NAMESPACE, false)) return false;
  bool ok = prefs.putBytes("cal", &cal, sizeof(CalData)) == sizeof(CalData) &&
            prefs.putUShort("ver", cal.version) > 0;
  prefs.end();
  return ok;
}

void storageClear() {
  if (!prefs.begin(NVS_NAMESPACE, false)) return;
  prefs.clear();
  prefs.end();
}
