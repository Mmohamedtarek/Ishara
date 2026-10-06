#include "ble.h"
#include <stdarg.h>
#include "board.h"
#include "config.h"

#if BLE_ENABLED

#include <NimBLEDevice.h>
#include <atomic>
#include <esp_mac.h>
#include "calibration.h"
#include "console.h"

static const char* const UUID_SERVICE = "6e1a0001-7b5c-4f3a-9a62-1d2c3b4a5f60";
static const char* const UUID_DATA = "6e1a0002-7b5c-4f3a-9a62-1d2c3b4a5f60";
static const char* const UUID_CMD = "6e1a0003-7b5c-4f3a-9a62-1d2c3b4a5f60";
static const char* const UUID_EVENT = "6e1a0004-7b5c-4f3a-9a62-1d2c3b4a5f60";
static const char* const UUID_INFO = "6e1a0005-7b5c-4f3a-9a62-1d2c3b4a5f60";

static const uint8_t SAMPLE_BYTES = BLE_CHANNELS * 2;
static const uint8_t ATT_OVERHEAD = 3;  // notification payload = MTU - 3

static char g_name[16] = "off";
static NimBLEServer* g_server = nullptr;
static NimBLECharacteristic* g_data = nullptr;
static NimBLECharacteristic* g_event = nullptr;

// Written by the NimBLE task, read by the loop task.
static std::atomic<bool> g_connected{false};
static std::atomic<uint16_t> g_conn{0};
static std::atomic<bool> g_linkUp{false};        // connected, not handled yet
static std::atomic<bool> g_linkDown{false};      // disconnected, not handled yet
static std::atomic<bool> g_eventSub{false};      // app subscribed to EVENT, not handled yet
struct Cmd {
  char s[BLE_CMD_MAX + 4];
};
static QueueHandle_t g_cmdQueue = nullptr;

// Loop task only.
static bool g_stream = false;
static uint8_t g_frame[BLE_FRAME_HEADER + SAMPLE_BYTES * BLE_SAMPLES_PER_FRAME];
static uint8_t g_frameN = 0;     // samples in g_frame so far
static uint8_t g_frameSize = 0;  // samples this frame will hold

static uint16_t mtu() { return g_connected ? g_server->getPeerMTU(g_conn) : 0; }

// Samples per frame for the current MTU (section 4); 0 = the MTU is too small to stream.
static uint8_t samplesPerFrame() {
  uint16_t m = mtu();
  if (m < ATT_OVERHEAD + BLE_FRAME_HEADER + SAMPLE_BYTES) return 0;
  return min<uint16_t>(BLE_SAMPLES_PER_FRAME, (m - ATT_OVERHEAD - BLE_FRAME_HEADER) / SAMPLE_BYTES);
}

static void put16(uint8_t* p, uint16_t v) {
  p[0] = v & 0xFF;
  p[1] = v >> 8;
}

// ---------- NimBLE callbacks (NimBLE task) ----------

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, ble_gap_conn_desc* desc) override {
    if (g_connected) {  // one central at a time
      server->disconnect(desc->conn_handle);
      return;
    }
    g_conn = desc->conn_handle;
    g_connected = true;
    g_linkUp = true;
    server->updateConnParams(desc->conn_handle, BLE_CONN_MIN, BLE_CONN_MAX, 0, BLE_CONN_TIMEOUT);
  }
  void onDisconnect(NimBLEServer*, ble_gap_conn_desc* desc) override {
    if (!g_connected || desc->conn_handle != g_conn) return;  // the refused second central
    g_connected = false;
    g_linkDown = true;
    NimBLEDevice::startAdvertising();
  }
};

class CmdCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, ble_gap_conn_desc*) override {
    NimBLEAttValue v = c->getValue();
    Cmd cmd;
    size_t n = min<size_t>(v.length(), sizeof(cmd.s) - 1);
    memcpy(cmd.s, v.data(), n);
    cmd.s[n] = 0;
    xQueueSend(g_cmdQueue, &cmd, 0);  // a full queue drops the command (the app would time out)
  }
};

class EventCb : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic*, ble_gap_conn_desc*, uint16_t subValue) override {
    if (subValue & 1) g_eventSub = true;
  }
};

// ---------- loop task ----------

void bleEvent(const char* fmt, ...) {
  if (!g_connected) return;
  char line[512];  // the longest line is #CAL (~330 bytes)
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(line, sizeof(line) - 1, fmt, ap);
  va_end(ap);
  if (n < 0) return;
  n = min<int>(n, sizeof(line) - 2);
  line[n++] = '\n';
  // A line longer than one notification is split; the app joins bytes until '\n'.
  uint16_t m = mtu();
  size_t chunk = m > ATT_OVERHEAD ? m - ATT_OVERHEAD : 20;
  for (int off = 0; off < n; off += chunk)
    g_event->notify((const uint8_t*)line + off, min<size_t>(chunk, n - off));
}

static void batLine() {
  char line[40];
  BatState st = batteryState();
  // Unknown only happens while a first LOW reading is being debounced, so report LOW.
  batteryStateLine(st == BatState::Unknown ? BatState::Low : st, line, sizeof(line));
  bleEvent("%s", line);
}

static void streamStop() {
  g_stream = false;
  g_frameN = 0;
}

static void handleCommand(char* cmd) {
  // Trim trailing CR / LF / spaces (some BLE tools add them) and upper-case it.
  size_t len = strlen(cmd);
  while (len && isspace((unsigned char)cmd[len - 1])) cmd[--len] = 0;
  if (!len) return;
  for (char* p = cmd; *p; p++) *p = toupper((unsigned char)*p);
  say("BLE command %s", cmd);

  char* arg = strchr(cmd, ' ');
  if (arg) {
    *arg++ = 0;
    while (*arg == ' ') arg++;
  } else {
    arg = cmd + len;  // ""
  }

  if (!strcmp(cmd, "STREAM")) {
    if (!strcmp(arg, "1")) {
      if (!samplesPerFrame()) {
        bleEvent("#ERR STREAM MTU");
        return;
      }
      streamStop();  // start on a fresh frame
      g_stream = true;
      bleEvent("#OK STREAM");
    } else if (!strcmp(arg, "0")) {
      streamStop();
      bleEvent("#OK STREAM");
    } else {
      bleEvent("#ERR STREAM ARG");
    }
  } else if (!strcmp(cmd, "GETCAL")) {
    const char* j = calJson();
    bleEvent("#CAL %s", j ? j : "NONE");
  } else if (!strcmp(cmd, "CAL")) {
    calBleCommand(arg);
  } else if (!strcmp(cmd, "BAT")) {
    batLine();
  } else if (!strcmp(cmd, "PING")) {
    bleEvent("#PONG");
  } else {
    bleEvent("#ERR %s UNKNOWN", cmd);
  }
}

void bleBegin() {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  snprintf(g_name, sizeof(g_name), "Ishara-%02X%02X", mac[4], mac[5]);
  g_cmdQueue = xQueueCreate(8, sizeof(Cmd));

  NimBLEDevice::init(g_name);
  NimBLEDevice::setMTU(BLE_MTU);
  g_server = NimBLEDevice::createServer();
  g_server->setCallbacks(new ServerCb());
  g_server->advertiseOnDisconnect(false);  // ServerCb restarts it (only for the real central)

  NimBLEService* svc = g_server->createService(UUID_SERVICE);
  g_data = svc->createCharacteristic(UUID_DATA, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* cmd =
      svc->createCharacteristic(UUID_CMD, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  cmd->setCallbacks(new CmdCb());
  g_event = svc->createCharacteristic(UUID_EVENT, NIMBLE_PROPERTY::NOTIFY);
  g_event->setCallbacks(new EventCb());

  char info[192];
  snprintf(info, sizeof(info),
           "{\"proto\":%u,\"fw\":\"%s\",\"board\":\"%s\",\"rate_hz\":%lu,\"channels\":%u,"
           "\"acc_lsb_per_g\":%.0f,\"gyro_lsb_per_dps\":%.1f,\"flex_max\":%u,"
           "\"samples_per_frame\":%u}",
           BLE_PROTO, FW_VERSION, BOARD_NAME, (unsigned long)(1000 / SAMPLE_PERIOD_MS),
           BLE_CHANNELS, ACCEL_LSB_PER_G, GYRO_LSB_PER_DPS, ADC_MAX, BLE_SAMPLES_PER_FRAME);
  NimBLECharacteristic* infoChr = svc->createCharacteristic(UUID_INFO, NIMBLE_PROPERTY::READ);
  infoChr->setValue((const uint8_t*)info, strlen(info));
  svc->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(UUID_SERVICE);
  adv->setScanResponse(true);  // the 128-bit UUID fills the advert, the name goes here
  adv->start();
}

void bleLoop() {
  if (g_linkDown.exchange(false)) {
    // Streaming stops and unsaved app calibration steps are dropped.
    streamStop();
    calBleDrop();
    say("BLE disconnected, advertising");
  }
  if (g_linkUp.exchange(false)) say("BLE connected");
  if (g_eventSub.exchange(false)) {
    batLine();  // "#BAT" at connect (sent once the app can hear it)
    if (!imuPresent()) bleEvent("#MPU FAIL");
  }
  Cmd cmd;
  while (xQueueReceive(g_cmdQueue, &cmd, 0) == pdTRUE) handleCommand(cmd.s);
}

void bleSample(const Sample& s, uint16_t seq) {
  if (!g_stream || !g_connected) return;
  if (g_frameN == 0) {
    g_frameSize = samplesPerFrame();
    if (!g_frameSize) {  // MTU went down mid-stream
      streamStop();
      bleEvent("#ERR STREAM MTU");
      return;
    }
    g_frame[0] = BLE_FRAME_VER;
    put16(g_frame + 2, seq);  // seq of the first sample
  }
  uint8_t* p = g_frame + BLE_FRAME_HEADER + g_frameN * SAMPLE_BYTES;
  for (uint8_t f = 0; f < NUM_FINGERS; f++, p += 2) put16(p, s.flex[f]);
  for (int i = 0; i < 3; i++, p += 2) put16(p, (uint16_t)s.accel[i]);
  for (int i = 0; i < 3; i++, p += 2) put16(p, (uint16_t)s.gyro[i]);
  if (++g_frameN < g_frameSize) return;
  g_frame[1] = g_frameN;
  g_data->notify(g_frame, BLE_FRAME_HEADER + g_frameN * SAMPLE_BYTES);
  g_frameN = 0;
}

const char* bleName() { return g_name; }

#else  // BLE_ENABLED

void bleBegin() {}
void bleLoop() {}
void bleSample(const Sample&, uint16_t) {}
const char* bleName() { return "off"; }
void bleEvent(const char*, ...) {}

#endif
