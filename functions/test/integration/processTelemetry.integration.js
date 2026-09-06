// End-to-end test of processTelemetry against the Firestore emulator.
// Run with `npm run test:integration` (see README.md in this folder).
//
// Test devices have no ownerId, so no notification is ever sent.

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error(
    "FIRESTORE_EMULATOR_HOST is not set. Run this with `npm run test:integration`; " +
      "without the emulator the Admin SDK would write to the production database."
  );
}

const test = require("node:test");
const assert = require("node:assert");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

function uniqueId(prefix) {
  return `${prefix}-${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

async function waitFor(check, { timeoutMs = 15000, intervalMs = 300, message = "condition" } = {}) {
  const start = Date.now();
  for (;;) {
    const result = await check();
    if (result) return result;
    if (Date.now() - start > timeoutMs) {
      throw new Error(`Timed out after ${timeoutMs} ms waiting for: ${message}`);
    }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

const ZONE_CENTER = { lat: 38.7223, lng: -9.1393 };
const ZONE_RADIUS = 100;
const INSIDE_POINT = { lat: 38.7223, lng: -9.1393 };
const OUTSIDE_POINT = { lat: 38.73, lng: -9.1393 }; // ~860 m north

async function seedDevice(deviceId, zoneName = "Home") {
  await db.doc(`devices/${deviceId}`).set({ name: `Device ${deviceId}` });
  await db.doc(`devices/${deviceId}/geofences/zone-1`).set({
    name: zoneName,
    type: "circle",
    active: true,
    center: new admin.firestore.GeoPoint(ZONE_CENTER.lat, ZONE_CENTER.lng),
    radius: ZONE_RADIUS,
    color: "#534AB7",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function addTelemetry(deviceId, point, extra = {}) {
  return db.collection(`devices/${deviceId}/telemetry`).add({
    lat: point.lat,
    lng: point.lng,
    battery: 80,
    timestamp: Date.now(),
    source: "gps",
    accuracy: 0,
    ...extra,
  });
}

async function getDevice(deviceId) {
  return (await db.doc(`devices/${deviceId}`).get()).data();
}

async function openAlerts(deviceId, type) {
  const snap = await db
    .collection("alerts")
    .where("deviceId", "==", deviceId)
    .where("type", "==", type)
    .where("resolved", "==", false)
    .get();
  return snap.docs;
}

test("first reading outside all zones does not alert", async () => {
  const deviceId = uniqueId("dev-debounce");
  await seedDevice(deviceId);

  await addTelemetry(deviceId, OUTSIDE_POINT);

  await waitFor(
    async () => {
      const device = await getDevice(deviceId);
      return device && device.outsideCount === 1;
    },
    { message: "outsideCount to reach 1" }
  );

  const alerts = await openAlerts(deviceId, "geofence_exit");
  assert.strictEqual(alerts.length, 0);
});

test("second consecutive reading outside creates a geofence_exit alert", async () => {
  const deviceId = uniqueId("dev-alert");
  await seedDevice(deviceId, "Home");

  await addTelemetry(deviceId, OUTSIDE_POINT);
  await waitFor(async () => (await getDevice(deviceId))?.outsideCount === 1, {
    message: "first outside reading",
  });

  await addTelemetry(deviceId, OUTSIDE_POINT);

  const alerts = await waitFor(
    async () => {
      const docs = await openAlerts(deviceId, "geofence_exit");
      return docs.length > 0 ? docs : null;
    },
    { message: "geofence_exit alert" }
  );

  assert.strictEqual(alerts.length, 1);
  const alert = alerts[0].data();
  assert.strictEqual(alert.zoneName, "Home");
  assert.strictEqual(alert.resolved, false);
  assert.strictEqual(typeof alert.distance, "number");

  const device = await getDevice(deviceId);
  assert.strictEqual(device.alertActive, true);
});

test("returning to a zone resolves the open alert", async () => {
  const deviceId = uniqueId("dev-resolve");
  await seedDevice(deviceId, "Home");

  await addTelemetry(deviceId, OUTSIDE_POINT);
  await waitFor(async () => (await getDevice(deviceId))?.outsideCount === 1, {
    message: "first outside reading",
  });
  await addTelemetry(deviceId, OUTSIDE_POINT);
  await waitFor(async () => (await openAlerts(deviceId, "geofence_exit")).length > 0, {
    message: "alert created",
  });

  await addTelemetry(deviceId, INSIDE_POINT);

  await waitFor(async () => (await openAlerts(deviceId, "geofence_exit")).length === 0, {
    message: "alert resolved",
  });

  const device = await getDevice(deviceId);
  assert.strictEqual(device.alertActive, false);
  assert.strictEqual(device.outsideCount, 0);
});

test("an imprecise Wi-Fi reading near the edge does not count towards the debounce", async () => {
  const deviceId = uniqueId("dev-uncertain");
  await seedDevice(deviceId, "Home");

  // ~122 m from the center (outside the 100 m radius) with 150 m accuracy.
  const nearEdge = { lat: 38.7234, lng: -9.1393 };
  await addTelemetry(deviceId, nearEdge, { source: "wifi", accuracy: 150 });

  // An uncertain reading changes nothing, so wait and check nothing moved.
  await new Promise((r) => setTimeout(r, 3000));
  const device = await getDevice(deviceId);
  assert.strictEqual(device.outsideCount ?? 0, 0);

  const alerts = await openAlerts(deviceId, "geofence_exit");
  assert.strictEqual(alerts.length, 0);
});
