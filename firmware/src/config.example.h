// Firmware configuration template. Copy to config.h (git-ignored) and fill in.
#ifndef CONFIG_H
#define CONFIG_H

// Must exist in Firestore as devices/{DEVICE_ID}.
#define DEVICE_ID   "your-device-id"

// Must match DEVICE_KEY in functions/.env (sent as X-Device-Key).
#define DEVICE_KEY  "your-device-key"

// ingestTelemetry endpoint.
#define SERVER_HOST "europe-west1-<PROJECT_ID>.cloudfunctions.net"
#define SERVER_PATH "/ingestTelemetry"
#define SERVER_PORT 443

// SIM card APN.
#define GPRS_APN    "TM"
#define GPRS_USER   ""
#define GPRS_PASS   ""

// Deep sleep between cycles and total GPS time budget per cycle, in seconds.
#define INTERVAL_S     20
#define GPS_TIMEOUT_S  90

// Time spent trying for a fix with the cellular radio still on before
// switching it off. 0 always switches it off.
#define GPS_FAST_TIMEOUT_S  20

// After this many cycles without a fix the device assumes it is indoors and
// limits the GPS attempt to GPS_INDOOR_TIMEOUT_S.
#define GPS_INDOOR_TIMEOUT_S  15
#define INDOOR_AFTER_N_MISSES 2

// Indoor positioning from a Wi-Fi scan, resolved by the backend.
#define WIFI_FALLBACK   1
#define WIFI_MAX_APS    12

#endif  // CONFIG_H
