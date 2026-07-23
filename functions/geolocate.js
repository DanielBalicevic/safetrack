// Indoor positioning: resolves a Wi-Fi scan from the device into coordinates
// using the Google Geolocation API. Done server-side so the API key never
// ships with the firmware.
//
// Requires GEOLOCATION_API_KEY in functions/.env (a key restricted to the
// Geolocation API).

const logger = require("firebase-functions/logger");

const ENDPOINT = "https://www.googleapis.com/geolocation/v1/geolocate";
const TIMEOUT_MS = 5000;

// The API needs at least two access points to produce a useful estimate.
const MIN_APS = 2;

const MAC_RE = /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/;

function normalizeAccessPoints(wifi) {
  if (!Array.isArray(wifi)) return [];
  const out = [];
  for (const ap of wifi) {
    if (!ap || typeof ap.mac !== "string" || !MAC_RE.test(ap.mac)) continue;
    const rssi = Number(ap.rssi);
    if (!Number.isFinite(rssi)) continue;
    out.push({ macAddress: ap.mac.toLowerCase(), signalStrength: rssi });
  }
  return out;
}

// Returns { lat, lng, accuracy } or null when no position can be resolved.
async function locateByWifi(wifi) {
  const apiKey = process.env.GEOLOCATION_API_KEY;
  if (!apiKey) {
    logger.error("GEOLOCATION_API_KEY is not set; Wi-Fi positioning disabled.");
    return null;
  }

  const wifiAccessPoints = normalizeAccessPoints(wifi);
  const received = Array.isArray(wifi) ? wifi.length : 0;

  // Logging the scan makes it possible to tell a bad scan apart from missing
  // coverage in Google's database when the API returns 404.
  const summary = wifiAccessPoints
    .map((ap) => `${ap.macAddress}@${ap.signalStrength}`)
    .join(" ");
  logger.info(`Wi-Fi: ${received} received, ${wifiAccessPoints.length} valid | ${summary}`);

  if (wifiAccessPoints.length < MIN_APS) {
    logger.warn(`Wi-Fi: only ${wifiAccessPoints.length} valid AP(s), need ${MIN_APS}.`);
    return null;
  }

  try {
    const res = await fetch(`${ENDPOINT}?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      // Without considerIp the API falls back to the cellular gateway's IP,
      // which can be tens of kilometers off.
      body: JSON.stringify({ considerIp: false, wifiAccessPoints }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    if (!res.ok) {
      const detail = res.status === 404 ? "unknown access points" : await res.text();
      logger.warn(`Geolocation API ${res.status}: ${detail}`);
      return null;
    }

    const data = await res.json();
    const lat = data && data.location && data.location.lat;
    const lng = data && data.location && data.location.lng;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      logger.warn("Geolocation API response has no location.");
      return null;
    }

    const accuracy = Number.isFinite(data.accuracy) ? Math.round(data.accuracy) : 100;
    logger.info(`Wi-Fi resolved: ${lat},${lng} (+-${accuracy} m, ${wifiAccessPoints.length} APs)`);
    return { lat, lng, accuracy };
  } catch (err) {
    logger.error("Geolocation API request failed:", err);
    return null;
  }
}

module.exports = { locateByWifi, normalizeAccessPoints, MIN_APS };
