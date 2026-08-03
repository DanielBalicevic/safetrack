// Device simulator: posts telemetry to ingestTelemetry like the real tracker,
// so the backend can be tested end to end without hardware.
//
// Modes:
//   --inside   stays near the zone center (no alert)
//   --escape   moves away until it leaves the zone (alert)
//   --return   leaves and comes back (alert, then resolved)
//   --indoor   sends a Wi-Fi scan instead of coordinates
//
// Usage:
//   DEVICE_KEY=<key> node simulate.js --escape
//   DEVICE_KEY=<key> node simulate.js --inside --once
//
// Environment: ENDPOINT, DEVICE_KEY, DEVICE_ID, WIFI_APS ("mac@rssi,mac@rssi").

const ENDPOINT =
  process.env.ENDPOINT ||
  "https://europe-west1-safetrack-b46b1.cloudfunctions.net/ingestTelemetry";
const DEVICE_KEY = process.env.DEVICE_KEY;
const DEVICE_ID = process.env.DEVICE_ID || "device-teste-01";

if (!DEVICE_KEY) {
  console.error("Set DEVICE_KEY (the same value as in functions/.env).");
  process.exit(1);
}

// Zone center used by the test zones.
const CENTER_LAT = 37.0998678;
const CENTER_LNG = -8.2281563;

const INTERVAL_MS = 30 * 1000;
let battery = 92;

const M_PER_DEG_LAT = 111320;

// Point `meters` north of the center.
function pointAtMeters(meters) {
  return { lat: CENTER_LAT + meters / M_PER_DEG_LAT, lng: CENTER_LNG };
}

// Distance from the center, in meters, for each step.
const TRAJECTORIES = {
  inside: [10, 20, 15, 30, 25, 12, 18],
  escape: [20, 60, 110, 160, 220, 300, 380],
  return: [20, 90, 170, 260, 170, 80, 15],
};

// Made-up access points. The Geolocation API will not recognise them and the
// backend answers 422; pass real ones with WIFI_APS to get a position.
const SAMPLE_APS = [
  { mac: "a4:2b:b0:11:22:33", rssi: -48 },
  { mac: "e8:9f:80:44:55:66", rssi: -61 },
  { mac: "3c:37:86:77:88:99", rssi: -73 },
];

function wifiAccessPoints() {
  const raw = process.env.WIFI_APS;
  if (!raw) return SAMPLE_APS;
  return raw.split(",").map((pair) => {
    const [mac, rssi] = pair.trim().split("@");
    return { mac, rssi: Number(rssi) || -70 };
  });
}

async function sendPoint(index, meters, indoor) {
  battery = Math.max(0, battery - 1);

  const payload = indoor
    ? { deviceId: DEVICE_ID, battery, source: "wifi", wifi: wifiAccessPoints(), timestamp: Date.now() }
    : { deviceId: DEVICE_ID, ...pointAtMeters(meters), battery, source: "gps", timestamp: Date.now() };

  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Device-Key": DEVICE_KEY },
      body: JSON.stringify(payload),
    });
    const text = await res.text();
    const where = indoor ? `indoor (${payload.wifi.length} APs)` : `${meters} m from center`;
    console.log(`[#${index}] ${where} | battery ${battery}% | HTTP ${res.status} | ${text}`);
  } catch (err) {
    console.error(`[#${index}] network error:`, err.message);
  }
}

function parseArgs() {
  const args = process.argv.slice(2);
  const modes = ["escape", "return", "indoor", "inside"];
  const mode = modes.find((m) => args.includes(`--${m}`)) || "inside";
  return { mode, once: args.includes("--once") };
}

async function main() {
  const { mode, once } = parseArgs();
  const indoor = mode === "indoor";
  const trajectory = indoor ? [0, 0, 0] : TRAJECTORIES[mode];

  console.log(`Endpoint: ${ENDPOINT}`);
  console.log(`Device:   ${DEVICE_ID}`);
  console.log(`Mode:     ${mode}${once ? " (single point)" : ""}`);

  let i = 0;
  const step = async () => {
    await sendPoint(i + 1, trajectory[i % trajectory.length], indoor);
    i++;
    if (once || i >= trajectory.length) process.exit(0);
  };

  await step();
  if (!once) setInterval(step, INTERVAL_MS);
}

main();
