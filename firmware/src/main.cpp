// SafeTrack device firmware.
// Board: LilyGO T-SIM7000G (ESP32 + SIM7000G modem with GNSS).
//
// Every wake-up from deep sleep runs one cycle: get a GPS fix (or a Wi-Fi scan
// indoors), read the battery, send any queued points from the MicroSD card,
// send the current point over HTTPS and go back to sleep.

#include <Arduino.h>
#include <TinyGsmClient.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <SD.h>
#include <WiFi.h>   // used only to scan for access points, never to connect
#include <vector>
#include <algorithm>
#include "config.h"
#include "sim7000_http.h"

// ------------------------------------------------------------
// LilyGO T-SIM7000G pins
// ------------------------------------------------------------
#define MODEM_TX     27
#define MODEM_RX     26
#define MODEM_PWRKEY 4
#define MODEM_DTR    25

#define SD_MISO      2
#define SD_MOSI      15
#define SD_SCLK      14
#define SD_CS        13

#define BAT_ADC      35   // battery voltage through a 1:2 divider

#define UART_BAUD    115200

// ------------------------------------------------------------
// Constants
// ------------------------------------------------------------
#define uS_PER_S        1000000ULL
#define QUEUE_DIR       "/queue"
#define MAX_FLUSH       20       // queued points sent per cycle
#define BAT_EMPTY_MV    3300
#define BAT_FULL_MV     4200

// Keep the modem and GNSS powered during deep sleep so the GNSS keeps its
// ephemeris and the next fix is a hot start (~1 s instead of 30-90 s).
#define KEEP_MODEM_WARM 1

// Set to 0 to skip the MicroSD card entirely.
#define SD_ENABLED      1

// Keep the network registration and PDP context alive between cycles.
// Re-registering and the TLS handshake cost 10-30 s per cycle.
#define KEEP_NETWORK_WARM 1

// Writes one CSV row per cycle (battery and active time) to measure real
// battery life. See tools/analyze-energy-log.js.
#define ENERGY_LOG_ENABLED 1
#define ENERGY_LOG_PATH    "/log/energy.csv"

// ------------------------------------------------------------
// Globals
// ------------------------------------------------------------
#define SerialMon Serial
#define SerialAT  Serial1

TinyGsm     modem(SerialAT);
// HTTP(S) through the modem's native SH stack. TinyGSM's socket read path
// does not work reliably on this modem.
Sim7000Http shHttp(SerialAT, SerialMon);

SPIClass sdSPI(VSPI);
bool     sdOk = false;

RTC_DATA_ATTR uint32_t bootCount = 0;
// Consecutive cycles without a GPS fix, used to detect that we are indoors.
RTC_DATA_ATTR uint32_t noFixStreak = 0;

void logln(const String& msg) { SerialMon.println(msg); }
void logln(const char* msg)   { SerialMon.println(msg); }

// ------------------------------------------------------------
// Modem power
// ------------------------------------------------------------

// Idempotent: the PWRKEY pulse toggles the modem, so it is only sent when the
// modem does not answer.
void modemEnsureOn() {
  SerialAT.begin(UART_BAUD, SERIAL_8N1, MODEM_RX, MODEM_TX);

  if (modem.testAT(2000)) {
    logln("[MODEM] already on (warm start).");
    return;
  }

  logln("[MODEM] powering on...");
  pinMode(MODEM_PWRKEY, OUTPUT);
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(300);
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1200);                       // SIM7000 needs a pulse longer than 1 s
  digitalWrite(MODEM_PWRKEY, HIGH);
  delay(3000);

  if (!modem.testAT(10000)) {
    logln("[MODEM] no AT response, trying init anyway.");
  }
  modem.init();
  logln("[MODEM] " + modem.getModemInfo());
}

// The cellular transmitter desensitizes the GNSS receiver (the antennas are
// centimeters apart). Airplane mode (CFUN=4) frees the GNSS while keeping its
// state.
void cellRadioOff() {
  logln("[RF] cellular radio off (CFUN=4).");
  modem.setPhoneFunctionality(4);
  delay(200);
}

void cellRadioOn() {
  logln("[RF] cellular radio on (CFUN=1).");
  modem.setPhoneFunctionality(1);
  delay(500);
}

void modemEndCycle() {
#if KEEP_MODEM_WARM
#if KEEP_NETWORK_WARM
  logln("[MODEM] keeping GNSS and network registration for the next cycle.");
#else
  cellRadioOff();
  logln("[MODEM] keeping GNSS on, cellular radio off until the next send.");
#endif
#else
  logln("[MODEM] powering off.");
  modem.disableGPS();
  modem.poweroff();
  delay(1000);
#endif
}

// ------------------------------------------------------------
// GNSS
// ------------------------------------------------------------

struct GpsFix {
  bool  valid = false;
  float lat = 0, lng = 0;
  int   year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;
};

// Polls for a fix for up to `timeoutMs`. Assumes the GNSS is already on.
GpsFix getGpsFix(uint32_t timeoutMs) {
  GpsFix fix;
  uint32_t start = millis();

  while (millis() - start < timeoutMs) {
    float lat = 0, lng = 0;
    int yr = 0, mo = 0, dy = 0, hr = 0, mi = 0, se = 0;
    if (modem.getGPS(&lat, &lng, 0, 0, 0, 0, 0, &yr, &mo, &dy, &hr, &mi, &se)) {
      fix.valid  = true;
      fix.lat = lat; fix.lng = lng;
      fix.year = yr; fix.month = mo; fix.day = dy;
      fix.hour = hr; fix.minute = mi; fix.second = se;
      logln("[GPS] fix: " + String(lat, 6) + ", " + String(lng, 6));
      return fix;
    }
    delay(1000);
  }

  return fix;
}

// Two-phase acquisition:
//   1. Try with the cellular radio on, which keeps the network registration.
//      With a warm GNSS this usually succeeds within a second or two.
//   2. If that fails, switch the radio off and use the remaining time budget.
// `radioWasOff` tells the caller to turn the radio back on before sending.
GpsFix acquireFix(bool& radioWasOff) {
  radioWasOff = false;

  // After a few cycles without a fix we are probably indoors; spend less time
  // on GPS and move on to the Wi-Fi scan.
  const bool likelyIndoors = noFixStreak >= INDOOR_AFTER_N_MISSES;
  const uint32_t budgetS = likelyIndoors ? GPS_INDOOR_TIMEOUT_S : GPS_TIMEOUT_S;
  if (likelyIndoors) {
    logln("[GPS] " + String(noFixStreak) + " cycles without a fix, assuming indoors (" +
          String(budgetS) + " s budget).");
  }

  uint32_t fastS = GPS_FAST_TIMEOUT_S;
  if (fastS > budgetS) fastS = budgetS;

#if GPS_FAST_TIMEOUT_S > 0
  GpsFix fix = getGpsFix(fastS * 1000UL);
  if (fix.valid) return fix;

  const uint32_t remainingS = (budgetS > fastS) ? (budgetS - fastS) : 0;
  if (remainingS == 0) { logln("[GPS] timeout, no fix."); return fix; }

  logln("[GPS] no fast fix, retrying with the radio off (" + String(remainingS) + " s).");
  cellRadioOff();
  radioWasOff = true;
  fix = getGpsFix(remainingS * 1000UL);
#else
  cellRadioOff();
  radioWasOff = true;
  GpsFix fix = getGpsFix(budgetS * 1000UL);
#endif

  if (!fix.valid) logln("[GPS] timeout, no fix.");
  return fix;
}

// ------------------------------------------------------------
// Battery
// ------------------------------------------------------------

uint32_t readBatteryMv() {
  uint32_t sum = 0;
  const int N = 16;
  for (int i = 0; i < N; i++) sum += analogReadMilliVolts(BAT_ADC);
  return (sum / N) * 2;   // undo the voltage divider
}

int batteryPercent(uint32_t mv) {
  if (mv <= BAT_EMPTY_MV) return 0;
  if (mv >= BAT_FULL_MV)  return 100;
  return (int)(((mv - BAT_EMPTY_MV) * 100L) / (BAT_FULL_MV - BAT_EMPTY_MV));
}

// ------------------------------------------------------------
// Time
// ------------------------------------------------------------

// UTC date/time to Unix seconds (Howard Hinnant's days_from_civil).
long toEpochSeconds(int y, int m, int d, int hh, int mm, int ss) {
  y -= m <= 2;
  long era = (y >= 0 ? y : y - 399) / 400;
  unsigned yoe = (unsigned)(y - era * 400);
  unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  long days = era * 146097 + (long)doe - 719468;
  return days * 86400L + hh * 3600L + mm * 60L + ss;
}

// Network time (NITZ) in milliseconds, or 0 if not available yet.
long long networkEpochMs() {
  int yr = 0, mo = 0, dy = 0, hr = 0, mi = 0, se = 0;
  float tz = 0;
  if (!modem.getNetworkTime(&yr, &mo, &dy, &hr, &mi, &se, &tz)) return 0;
  if (yr < 2020) return 0;
  long epoch = toEpochSeconds(yr, mo, dy, hr, mi, se);
  epoch -= (long)(tz * 900.0f);   // tz is in quarters of an hour
  return (long long)epoch * 1000LL;
}

// ------------------------------------------------------------
// Payloads
// ------------------------------------------------------------

String buildPayload(const GpsFix& fix, int battery) {
  JsonDocument doc;
  doc["deviceId"] = DEVICE_ID;
  doc["lat"]      = fix.lat;
  doc["lng"]      = fix.lng;
  doc["battery"]  = battery;
  doc["source"]   = "gps";

  long epoch = toEpochSeconds(fix.year, fix.month, fix.day,
                              fix.hour, fix.minute, fix.second);
  doc["timestamp"] = (long long)epoch * 1000LL;

  String out;
  serializeJson(doc, out);
  return out;
}

struct WifiAp {
  String mac;
  int32_t rssi;
};

// Indoors the GNSS sees no satellites. The visible access points are sent to
// the backend, which resolves them with the Google Geolocation API.
std::vector<WifiAp> scanWifi() {
  std::vector<WifiAp> aps;
#if !WIFI_FALLBACK
  return aps;
#else
  logln("[WIFI] scanning access points...");

  WiFi.mode(WIFI_STA);
  WiFi.disconnect(false, false);
  delay(100);

  // Active scan with 500 ms per channel. The default often returned a single
  // access point, and the API needs at least two.
  int n = WiFi.scanNetworks(/*async=*/false, /*show_hidden=*/true,
                            /*passive=*/false, /*max_ms_per_chan=*/500);
  if (n > 0) {
    for (int i = 0; i < n; i++) aps.push_back({ WiFi.BSSIDstr(i), WiFi.RSSI(i) });

    std::sort(aps.begin(), aps.end(),
              [](const WifiAp& a, const WifiAp& b) { return a.rssi > b.rssi; });
    if ((int)aps.size() > WIFI_MAX_APS) aps.resize(WIFI_MAX_APS);
  }

  WiFi.scanDelete();
  WiFi.mode(WIFI_OFF);

  logln("[WIFI] " + String(aps.size()) + " access point(s) found.");
  return aps;
#endif
}

// Without a timestamp the server uses the time of arrival.
String buildWifiPayload(const std::vector<WifiAp>& aps, int battery, long long epochMs) {
  JsonDocument doc;
  doc["deviceId"] = DEVICE_ID;
  doc["battery"]  = battery;
  doc["source"]   = "wifi";

  JsonArray arr = doc["wifi"].to<JsonArray>();
  for (const WifiAp& ap : aps) {
    JsonObject o = arr.add<JsonObject>();
    o["mac"]  = ap.mac;
    o["rssi"] = ap.rssi;
  }

  if (epochMs > 0) doc["timestamp"] = epochMs;

  String out;
  serializeJson(doc, out);
  return out;
}

// ------------------------------------------------------------
// MicroSD offline queue
// ------------------------------------------------------------

void sdSetup() {
#if !SD_ENABLED
  sdOk = false;
  return;
#endif
  sdSPI.begin(SD_SCLK, SD_MISO, SD_MOSI, SD_CS);
  if (!SD.begin(SD_CS, sdSPI)) {
    logln("[SD] mount failed, continuing without the offline queue.");
    sdOk = false;
    return;
  }
  sdOk = true;
  if (!SD.exists(QUEUE_DIR)) SD.mkdir(QUEUE_DIR);
  logln("[SD] ready.");
}

// Files are named <epoch seconds>.json so alphabetical order is chronological.
void sdEnqueue(const String& payload, long long epochMs) {
  if (!sdOk) { logln("[SD] no card, payload dropped."); return; }
  if (epochMs <= 0) {
    logln("[SD] payload has no reliable timestamp, not queued.");
    return;
  }
  long epoch = (long)(epochMs / 1000LL);
  String path = String(QUEUE_DIR) + "/" + String(epoch) + ".json";
  File f = SD.open(path, FILE_WRITE);
  if (!f) { logln("[SD] could not open " + path); return; }
  f.print(payload);
  f.close();
  logln("[SD] queued " + path);
}

std::vector<String> sdListQueue() {
  std::vector<String> names;
  if (!sdOk) return names;
  File dir = SD.open(QUEUE_DIR);
  if (!dir) return names;
  for (File entry = dir.openNextFile(); entry; entry = dir.openNextFile()) {
    if (!entry.isDirectory()) names.push_back(String(entry.name()));
    entry.close();
  }
  dir.close();
  std::sort(names.begin(), names.end());
  return names;
}

void energyLogInit() {
#if ENERGY_LOG_ENABLED
  if (!sdOk) return;
  if (!SD.exists("/log")) SD.mkdir("/log");
  if (!SD.exists(ENERGY_LOG_PATH)) {
    File f = SD.open(ENERGY_LOG_PATH, FILE_WRITE);
    if (f) {
      f.println("epochMs,bootCount,activeMs,batteryMv,batteryPct,fixValid,source,sent");
      f.close();
    }
  }
#endif
}

// epochMs may be 0 when no clock is available yet.
void energyLogRow(long long epochMs, uint32_t activeMs, uint32_t batteryMv,
                   int batteryPct, bool fixValid, const char* source, bool sent) {
#if ENERGY_LOG_ENABLED
  if (!sdOk) return;
  File f = SD.open(ENERGY_LOG_PATH, FILE_APPEND);
  if (!f) { logln("[ENERGY] could not open " ENERGY_LOG_PATH); return; }
  f.print(epochMs);   f.print(',');
  f.print(bootCount); f.print(',');
  f.print(activeMs);  f.print(',');
  f.print(batteryMv); f.print(',');
  f.print(batteryPct);f.print(',');
  f.print(fixValid ? 1 : 0); f.print(',');
  f.print(source);    f.print(',');
  f.println(sent ? 1 : 0);
  f.close();
#endif
}

// ------------------------------------------------------------
// HTTPS
// ------------------------------------------------------------

// TLS 1.2 with SNI but without server certificate validation: SIM7000G
// firmware R1529 fails to connect whenever a CA is configured. The channel is
// still encrypted and the device authenticates with the X-Device-Key header.
bool httpPost(const String& payload) {
  logln("[HTTP] POST " + String(SERVER_HOST) + String(SERVER_PATH));

  ShResponse r = shHttp.request(
      SERVER_HOST, SERVER_PORT, /*ssl=*/true, "POST", SERVER_PATH,
      "application/json",
      "X-Device-Key", DEVICE_KEY,
      payload,
      /*caName=*/nullptr);

  logln("[HTTP] status " + String(r.status) + " (step " + r.step + ") | " + r.body);
  return r.status == 200;
}

// Sends queued points in chronological order and deletes each one after a
// 200. Stops at the first failure to keep the order.
void flushQueue() {
  if (!sdOk) return;
  std::vector<String> names = sdListQueue();
  if (names.empty()) return;

  logln("[SD] " + String(names.size()) + " queued point(s).");
  int sent = 0;
  for (const String& name : names) {
    if (sent >= MAX_FLUSH) break;
    String path = String(QUEUE_DIR) + "/" + name;
    File f = SD.open(path, FILE_READ);
    if (!f) continue;
    String payload = f.readString();
    f.close();

    if (httpPost(payload)) {
      SD.remove(path);
      sent++;
    } else {
      logln("[SD] failed to send " + name + ", stopping.");
      break;
    }
  }
}

// ------------------------------------------------------------
// Cellular network
// ------------------------------------------------------------

// Returns immediately when the registration survived from the last cycle.
bool networkConnect() {
  if (modem.isNetworkConnected() && modem.isGprsConnected()) {
    logln("[NET] already registered.");
    return true;
  }

  logln("[NET] registering...");
  modem.setNetworkMode(2);   // automatic

  if (!modem.waitForNetwork(60000L)) {
    logln("[NET] registration failed.");
    return false;
  }
  logln("[NET] registered, signal " + String(modem.getSignalQuality()));

  if (!modem.gprsConnect(GPRS_APN, GPRS_USER, GPRS_PASS)) {
    logln("[NET] GPRS connection failed.");
    return false;
  }
  logln("[NET] connected, IP " + modem.getLocalIP());
  return true;
}

void goToSleep() {
  logln("[SLEEP] " + String(INTERVAL_S) + " s.");
  SerialMon.flush();
  esp_sleep_enable_timer_wakeup((uint64_t)INTERVAL_S * uS_PER_S);
  esp_deep_sleep_start();
}

// ------------------------------------------------------------
// HTTP diagnostics (build with `pio run -e diag`)
// ------------------------------------------------------------
// Runs requests of increasing complexity to find where HTTPS fails:
// plain HTTP, HTTPS without validation, the real endpoint, and the endpoint
// with each candidate root certificate.
#ifdef DIAG_HTTP
void runHttpDiagnostics() {
  logln("\n=== HTTP diagnostics ===");
  logln("[MODEM] " + modem.getModemInfo());

  if (!networkConnect()) {
    logln("[DIAG] no network.");
    goToSleep();
    return;
  }

  const String testJson =
      String("{\"deviceId\":\"" DEVICE_ID "\",\"lat\":38.7078,\"lng\":-9.1366,")
      + "\"battery\":90,\"timestamp\":1700000000000}";

  Sim7000Http sh(SerialAT, SerialMon);

  sh.loadCA(GTS_ROOT_R1_PEM,       GTS_ROOT_R1_NAME);
  sh.loadCA(WR2_PEM,               WR2_NAME);
  sh.loadCA(GTS_ROOT_R1_XSIGN_PEM, GTS_ROOT_R1_XSIGN_NAME);

  // Sync the clock so certificate validation runs against the real time.
  sh.syncClockNtp();
  sh.ignoreRtcTime = false;

  struct { const char* label; String host; uint16_t port; bool ssl;
           const char* method; const char* path; const char* ca; } tests[] = {
    {"T1 HTTP, no TLS        ", "example.com", 80,  false, "GET",  "/",          nullptr},
    {"T2 HTTPS, no validation", "example.com", 443, true,  "GET",  "/",          nullptr},
    {"T3 endpoint, no CA     ", SERVER_HOST,   SERVER_PORT, true, "POST", SERVER_PATH, nullptr},
    {"T4 CA = GTS Root R1    ", SERVER_HOST,   SERVER_PORT, true, "POST", SERVER_PATH, GTS_ROOT_R1_NAME},
    {"T5 CA = WR2            ", SERVER_HOST,   SERVER_PORT, true, "POST", SERVER_PATH, WR2_NAME},
    {"T6 CA = R1 cross-signed", SERVER_HOST,   SERVER_PORT, true, "POST", SERVER_PATH, GTS_ROOT_R1_XSIGN_NAME},
  };

  for (auto& t : tests) {
    logln(String("\n--- ") + t.label + " : " + t.method + " " + t.host + ":" + t.port + t.path);
    uint32_t t0 = millis();
    bool post = (strcmp(t.method, "POST") == 0);
    ShResponse r = sh.request(
        t.host, t.port, t.ssl, t.method, t.path,
        post ? "application/json" : nullptr,
        post ? "X-Device-Key" : nullptr, DEVICE_KEY,
        post ? testJson : String(""),
        t.ca);
    logln("  status=" + String(r.status) + " step=" + r.step + " " +
          String(millis() - t0) + " ms");
    logln("  body(" + String(r.body.length()) + "): " + r.body.substring(0, 120));
  }

  logln("\n=== done ===");
  while (true) { delay(10000); }
}
#endif  // DIAG_HTTP

// ------------------------------------------------------------
// GNSS diagnostics (build with `pio run -e gnss`)
// ------------------------------------------------------------
// Prints raw AT+CGNSINF output to tell an antenna problem (no satellites in
// view) apart from an acquisition problem (satellites in view, no fix).
#ifdef DIAG_GNSS
String atRaw(const char* cmd, const char* until = "OK", uint32_t timeout = 3000) {
  while (SerialAT.available()) SerialAT.read();
  SerialMon.print(">> "); SerialMon.println(cmd);
  SerialAT.print(cmd); SerialAT.print("\r\n");
  String buf; uint32_t t0 = millis(); bool got = false;
  while (millis() - t0 < timeout && !got) {
    while (SerialAT.available()) {
      buf += (char)SerialAT.read();
      if (buf.endsWith(until) || buf.endsWith("ERROR")) { got = true; break; }
    }
    if (!got) delay(3);
  }
  String s = buf; s.replace("\r", " "); s.replace("\n", " "); s.trim();
  SerialMon.print("<< "); SerialMon.println(s);
  return buf;
}

void runGnssDiagnostics() {
  logln("\n=== GNSS diagnostics ===");

  atRaw("AT+CGMR", "OK", 3000);
  atRaw("AT+GMR",  "OK", 3000);

  atRaw("AT+CFUN=4", "OK", 5000);
  delay(500);

  // Clean GNSS power cycle with all constellations enabled.
  atRaw("AT+CGNSPWR?", "OK", 2000);
  atRaw("AT+CGNSMOD?", "OK", 2000);
  atRaw("AT+CGNSPWR=0", "OK", 3000); delay(2000);
  atRaw("AT+CGNSPWR=1", "OK", 3000); delay(2000);
  atRaw("AT+CGNSMOD=1,1,1,1", "OK", 2000);

  atRaw("AT+CGNSCOLD", "OK", 5000);

  // Field 2: fix, field 15: GPS satellites in view, field 16: satellites used.
  for (int i = 0; i < 48; i++) {
    SerialMon.print("[t=" + String(i * 5) + "s] ");
    atRaw("AT+CGNSINF", "OK", 3000);
    delay(5000);
  }

  logln("\n=== done ===");
  while (true) { delay(10000); }
}
#endif  // DIAG_GNSS

// ------------------------------------------------------------
// Main cycle. Deep sleep restarts the program, so everything runs in setup().
// ------------------------------------------------------------
void setup() {
  SerialMon.begin(115200);
  delay(1000);
  bootCount++;
  logln("\n=== SafeTrack | cycle #" + String(bootCount) + " ===");
  uint32_t cycleStartMs = millis();

  analogReadResolution(12);
  analogSetPinAttenuation(BAT_ADC, ADC_11db);

  sdSetup();
  energyLogInit();
  modemEnsureOn();

#ifdef DIAG_HTTP
  runHttpDiagnostics();
  return;
#endif

#ifdef DIAG_GNSS
  runGnssDiagnostics();
  return;
#endif

  modem.enableGPS();
  bool radioWasOff = false;
  GpsFix fix = acquireFix(radioWasOff);
  noFixStreak = fix.valid ? 0 : (noFixStreak + 1);

  uint32_t mv = readBatteryMv();
  int battery = batteryPercent(mv);
  logln("[BAT] " + String(mv) + " mV, " + String(battery) + "%");

  // Scan before turning the cellular radio back on to avoid both running at once.
  std::vector<WifiAp> aps;
  if (!fix.valid) {
    aps = scanWifi();
    if (aps.empty()) {
      logln("[CYCLE] no GPS fix and no access points, skipping.");
      energyLogRow(0, millis() - cycleStartMs, mv, battery, false, "none", false);
      modemEndCycle();
      goToSleep();
      return;
    }
  }

  if (radioWasOff) cellRadioOn();

  String payload;
  long long epochMs;
  if (fix.valid) {
    payload = buildPayload(fix, battery);
    epochMs = (long long)toEpochSeconds(fix.year, fix.month, fix.day,
                                        fix.hour, fix.minute, fix.second) * 1000LL;
  } else {
    epochMs = networkEpochMs();
    payload = buildWifiPayload(aps, battery, epochMs);
  }
  logln("[PAYLOAD] " + payload);

  bool sentOk = false;
  if (networkConnect()) {
    flushQueue();
    sentOk = httpPost(payload);
    if (!sentOk) {
      logln("[CYCLE] send failed, queuing on SD.");
      sdEnqueue(payload, epochMs);
    }
#if !KEEP_NETWORK_WARM
    modem.gprsDisconnect();
#endif
  } else {
    logln("[CYCLE] no network, queuing on SD.");
    sdEnqueue(payload, epochMs);
  }

  energyLogRow(epochMs, millis() - cycleStartMs, mv, battery,
               fix.valid, fix.valid ? "gps" : "wifi", sentOk);

  modemEndCycle();
  goToSleep();
}

void loop() {
  // Not used: deep sleep restarts the program in setup().
}
