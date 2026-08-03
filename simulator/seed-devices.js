// Creates (or removes with --clean) synthetic devices sim-01..sim-NN, each
// with one active circular zone, for the load and security tests.
//
// Usage:
//   GOOGLE_APPLICATION_CREDENTIALS=./sa-key.json node seed-devices.js
//   GOOGLE_APPLICATION_CREDENTIALS=./sa-key.json node seed-devices.js --clean
//
// Options: --devices=N --prefix=sim --owner=<uid>

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, GeoPoint, FieldValue } = require("firebase-admin/firestore");

function arg(name, def) {
  const hit = process.argv.slice(2).find((a) => a.startsWith("--" + name + "="));
  return hit ? hit.split("=")[1] : def;
}

const N = parseInt(arg("devices", "10"), 10);
const PREFIX = arg("prefix", "sim");
const OWNER = arg("owner", null);
const CLEAN = process.argv.includes("--clean");

const CENTER_LAT = 37.0998678;
const CENTER_LNG = -8.2281563;
const RADIUS_M = 200;

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Set GOOGLE_APPLICATION_CREDENTIALS to a service account key file.");
  process.exit(1);
}

initializeApp({ credential: applicationDefault() });
const db = getFirestore();

function id(i) {
  return PREFIX + "-" + String(i + 1).padStart(2, "0");
}

async function clean() {
  for (let i = 0; i < N; i++) {
    const ref = db.collection("devices").doc(id(i));
    const zones = await ref.collection("geofences").get();
    for (const z of zones.docs) await z.ref.delete();
    const telemetry = await ref.collection("telemetry").limit(500).get();
    for (const t of telemetry.docs) await t.ref.delete();
    await ref.delete();
    console.log(`deleted ${id(i)} (${telemetry.size} telemetry points)`);
  }
}

async function seed() {
  for (let i = 0; i < N; i++) {
    const ref = db.collection("devices").doc(id(i));
    const doc = {
      name: "Sim " + id(i),
      createdAt: FieldValue.serverTimestamp(),
      synthetic: true,
      pairingCode: "654321",
    };
    if (OWNER) doc.ownerId = OWNER;
    await ref.set(doc, { merge: true });

    await ref.collection("geofences").doc("load-zone").set({
      name: "Load test zone",
      type: "circle",
      active: true,
      center: new GeoPoint(CENTER_LAT, CENTER_LNG),
      radius: RADIUS_M,
      color: "#0E7355",
    });
    console.log(`created ${id(i)} with a ${RADIUS_M} m zone`);
  }
}

(CLEAN ? clean() : seed())
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
