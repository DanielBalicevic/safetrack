// Offline alert test: moves a test device's lastSeen back 25 minutes, waits
// for checkDeviceHealth to raise an "offline" alert, then sends a point and
// checks that the alert is resolved.
//
// The device is temporarily assigned to OWNER_UID so the alert is created and
// the notification is delivered. Takes up to 12 minutes.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=./sa-key.json OWNER_UID=<uid> DEVICE_KEY=<key> \
//   node offline-test.js

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, Timestamp, GeoPoint, FieldValue } = require("firebase-admin/firestore");

const PROJECT = process.env.PROJECT_ID || "safetrack-b46b1";
const INGEST = process.env.ENDPOINT || `https://europe-west1-${PROJECT}.cloudfunctions.net/ingestTelemetry`;
const KEY = process.env.DEVICE_KEY;
const UID = process.env.OWNER_UID;
const DEVICE = process.env.TEST_DEVICE || "uc-cenarios";
const LAT = 37.0998678;
const LNG = -8.2281563;

if (!KEY || !UID || !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Set DEVICE_KEY, OWNER_UID and GOOGLE_APPLICATION_CREDENTIALS.");
  process.exit(1);
}

initializeApp({ credential: applicationDefault() });
const db = getFirestore();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function sendPoint() {
  const res = await fetch(INGEST, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Device-Key": KEY },
    body: JSON.stringify({ deviceId: DEVICE, lat: LAT + 0.0003, lng: LNG, battery: 88, source: "gps", timestamp: Date.now() }),
  });
  return res.status;
}

async function offlineAlertsSince(since) {
  const s = await db.collection("alerts").where("deviceId", "==", DEVICE).get();
  return s.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((a) => a.type === "offline" && a.timestamp.toMillis() >= since);
}

(async () => {
  const ref = db.collection("devices").doc(DEVICE);
  await ref.set({ ownerId: UID, name: "Test device" }, { merge: true });
  await ref.collection("geofences").doc("zone").set({
    name: "Test zone", type: "circle", active: true,
    center: new GeoPoint(LAT, LNG), radius: 200, color: "#0E7355",
  });

  const t0 = Date.now();
  await ref.update({
    lastSeen: Timestamp.fromMillis(Date.now() - 25 * 60 * 1000),
    offlineAlertActive: false,
  });
  console.log("lastSeen moved back 25 min, waiting for checkDeviceHealth...");

  let alert = null;
  for (let i = 0; i < 72 && !alert; i++) {
    await sleep(10000);
    alert = (await offlineAlertsSince(t0))[0];
  }

  if (!alert) {
    console.log("FAIL: no offline alert within 12 minutes.");
  } else {
    const detectedS = Math.round((alert.timestamp.toMillis() - t0) / 1000);
    console.log(`PASS: offline alert created after ${detectedS} s ` +
      `(silent ${Math.round(alert.silentMs / 60000)} min, last position ${alert.lat}, ${alert.lng}).`);

    await sleep(10000);
    const status = await sendPoint();
    await sleep(9000);
    const resolved = (await db.collection("alerts").doc(alert.id).get()).data().resolved;
    console.log(`${resolved ? "PASS" : "FAIL"}: alert resolved after the device reported again (HTTP ${status}).`);
  }

  await ref.update({ ownerId: FieldValue.delete() });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
