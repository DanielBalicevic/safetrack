// End-to-end alert lifecycle tests against the deployed backend: sends
// telemetry to ingestTelemetry and checks what processTelemetry wrote to
// Firestore (geofence exits, battery alerts, offline alerts, bad input).
//
// Uses its own test device with no owner, so no notification is ever sent.
// Takes 8-12 minutes because the offline test waits for checkDeviceHealth.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=./sa-key.json DEVICE_KEY=<key> node scenarios-test.js

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, GeoPoint, Timestamp } = require("firebase-admin/firestore");

const PROJECT = process.env.PROJECT_ID || "safetrack-b46b1";
const INGEST = process.env.ENDPOINT || `https://europe-west1-${PROJECT}.cloudfunctions.net/ingestTelemetry`;
const KEY = process.env.DEVICE_KEY;
const DEVICE = process.env.TEST_DEVICE || "uc-cenarios";

const LAT = 37.0998678;
const LNG = -8.2281563;
const RADIUS = 200;
const M_PER_DEG_LAT = 111320;

if (!KEY || !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Set DEVICE_KEY and GOOGLE_APPLICATION_CREDENTIALS.");
  process.exit(1);
}

initializeApp({ credential: applicationDefault() });
const db = getFirestore();
const deviceRef = db.collection("devices").doc(DEVICE);

const results = [];
let startedAt = null;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pointAt = (m) => ({ lat: LAT + m / M_PER_DEG_LAT, lng: LNG });

async function send({ meters = 0, battery = 90, accuracy = 5, noTimestamp = false, rawBody = null }) {
  let body = rawBody;
  if (body === null) {
    const p = { deviceId: DEVICE, ...pointAt(meters), battery, source: "gps", accuracy };
    if (!noTimestamp) p.timestamp = Date.now();
    body = JSON.stringify(p);
  }
  const res = await fetch(INGEST, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Device-Key": KEY },
    body,
  });
  return { status: res.status };
}

async function alerts() {
  const s = await db.collection("alerts").where("deviceId", "==", DEVICE).get();
  return s.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((a) => a.timestamp && a.timestamp.toMillis() >= startedAt)
    .sort((a, b) => a.timestamp.toMillis() - b.timestamp.toMillis());
}

async function deviceState() {
  const d = await deviceRef.get();
  return d.exists ? d.data() : {};
}

async function telemetryCount() {
  const s = await deviceRef.collection("telemetry").count().get();
  return s.data().count;
}

function check(name, expected, actual, ok) {
  results.push({ name, expected, actual, ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}\n      ${actual}`);
}

async function resetDevice() {
  await deviceRef.set({
    name: "Scenario tests", synthetic: true,
    outsideCount: 0, alertActive: false,
    lowBatteryAlertActive: false, offlineAlertActive: false,
    lastSeen: Timestamp.now(),
  }, { merge: true });
  await deviceRef.collection("geofences").doc("test-zone").set({
    name: "Test zone", type: "circle", active: true,
    center: new GeoPoint(LAT, LNG), radius: RADIUS, color: "#0E7355",
  });
}

async function geofenceTests() {
  await send({ meters: 30 }); await sleep(4000);

  await send({ meters: 500 }); await sleep(6000);
  let a = await alerts();
  check("Single reading outside the zone", "No alert (debounce)",
    `${a.length} alert(s), outsideCount = ${(await deviceState()).outsideCount}`, a.length === 0);

  await send({ meters: 600 }); await sleep(7000);
  a = await alerts();
  check("Two consecutive readings outside", "One geofence_exit alert",
    `${a.length} alert(s), type = ${a[0] && a[0].type}, distance ${a[0] && Math.round(a[0].distance)} m`,
    a.length === 1 && a[0].type === "geofence_exit");

  await send({ meters: 700 }); await sleep(5000);
  await send({ meters: 800 }); await sleep(6000);
  a = await alerts();
  check("Staying outside the zone", "No repeated alert", `${a.length} alert(s) in total`, a.length === 1);

  await send({ meters: 40 }); await sleep(7000);
  const exit = (await alerts()).find((x) => x.type === "geofence_exit");
  check("Returning to the zone", "Exit alert resolved", `resolved = ${exit && exit.resolved}`, !!(exit && exit.resolved));

  const before = (await alerts()).length;
  await send({ meters: RADIUS + 60, accuracy: 150 }); await sleep(5000);
  await send({ meters: RADIUS + 60, accuracy: 150 }); await sleep(7000);
  a = await alerts();
  check("Two imprecise readings (150 m accuracy, 60 m outside)", "No alert, debounce unchanged",
    `${a.length - before} new alert(s), outsideCount = ${(await deviceState()).outsideCount}`, a.length === before);
}

async function batteryTests() {
  await send({ meters: 30, battery: 90 }); await sleep(4000);
  const b0 = (await alerts()).length;
  await send({ meters: 30, battery: 18 }); await sleep(7000);
  let a = await alerts();
  const low = a.slice(b0)[0];
  check("Battery at or below 20%", "One low_battery alert",
    `${a.length - b0} alert(s), type = ${low && low.type}`, a.length - b0 === 1);

  const b1 = (await alerts()).length;
  await send({ meters: 30, battery: 21 }); await sleep(5000);
  await send({ meters: 30, battery: 19 }); await sleep(7000);
  a = await alerts();
  check("Battery oscillating between 19% and 21%", "No repeated alert (hysteresis)",
    `${a.length - b1} new alert(s)`, a.length === b1);

  await send({ meters: 30, battery: 35 }); await sleep(7000);
  const state = await deviceState();
  check("Battery recovers above 30%", "Alert re-armed",
    `lowBatteryAlertActive = ${state.lowBatteryAlertActive}`, state.lowBatteryAlertActive === false);
}

async function offlineTests() {
  console.log("\nWaiting up to 6 minutes for checkDeviceHealth...");
  const s0 = (await alerts()).length;
  await deviceRef.update({
    lastSeen: Timestamp.fromMillis(Date.now() - 20 * 60 * 1000),
    offlineAlertActive: false,
  });
  let offline = null;
  for (let i = 0; i < 36 && !offline; i++) {
    await sleep(10000);
    offline = (await alerts()).slice(s0).find((x) => x.type === "offline");
  }
  check("No communication for over 15 minutes", "Offline alert with last known position",
    offline
      ? `silent ${Math.round(offline.silentMs / 60000)} min, position present = ${offline.lat != null}`
      : "no offline alert within 6 minutes",
    !!offline);

  if (offline) {
    await send({ meters: 30 }); await sleep(8000);
    const after = (await alerts()).find((x) => x.id === offline.id);
    check("Device reports again", "Offline alert resolved", `resolved = ${after && after.resolved}`,
      !!(after && after.resolved));
  }
}

async function failureTests() {
  const before = await telemetryCount();
  let r = await send({ rawBody: `{"deviceId":"${DEVICE}","lat":"not-a-number"}` });
  await sleep(4000);
  const after = await telemetryCount();
  check("Malformed payload", "HTTP 400, nothing written",
    `HTTP ${r.status}, telemetry ${before} -> ${after}`, r.status === 400 && before === after);

  r = await send({ meters: 30, noTimestamp: true }); await sleep(4000);
  const last = await deviceRef.collection("telemetry").orderBy("receivedAt", "desc").limit(1).get();
  const d = last.empty ? {} : last.docs[0].data();
  check("Reading without a timestamp", "Accepted, server time recorded",
    `HTTP ${r.status}, receivedAt present = ${d.receivedAt != null}`, r.status === 200 && d.receivedAt != null);

  await deviceRef.update({ outsideCount: 0, alertActive: false });
  await send({ meters: 900 }); await sleep(5000);
  await send({ meters: 950 }); await sleep(7000);
  const exits = (await alerts()).filter((x) => x.type === "geofence_exit");
  await deviceRef.collection("geofences").doc("test-zone").delete();
  r = await send({ meters: 950 }); await sleep(5000);
  const stillThere = await db.collection("alerts").doc(exits[exits.length - 1].id).get();
  check("Deleting a zone with an open alert", "Alert kept, ingestion keeps working",
    `alert exists = ${stillThere.exists}, next ingest HTTP ${r.status}`, stillThere.exists && r.status === 200);
}

async function main() {
  console.log(`Test device: ${DEVICE}, circular zone of ${RADIUS} m\n`);
  await resetDevice();
  const old = await db.collection("alerts").where("deviceId", "==", DEVICE).get();
  for (const d of old.docs) await d.ref.delete();
  startedAt = Date.now();
  await sleep(1500);

  await geofenceTests();
  await batteryTests();
  await offlineTests();
  await failureTests();
  await resetDevice();

  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed.`);
  if (failed.length) console.log("Failed: " + failed.map((f) => f.name).join("; "));
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
