// Security tests against the deployed project. Talks to the Firebase REST
// APIs as an untrusted client would, so the Firestore rules are evaluated for
// real (the Admin SDK and the emulator would bypass or approximate them).
//
// Creates a throwaway account to act as a second caregiver and deletes it at
// the end. Only writes to the synthetic device SIM_DEVICE.
//
// Usage:
//   WEB_API_KEY=<firebase web key> OWNER_EMAIL=<email> OWNER_PASS=<password> \
//   DEVICE_KEY=<key> node security-test.js

const PROJECT = process.env.PROJECT_ID || "safetrack-b46b1";
const WEB_KEY = process.env.WEB_API_KEY;
const DEVICE = process.env.DEVICE_ID || "device-teste-01";
const SIM = process.env.SIM_DEVICE || "sim-10";
const PAIRING_CODE = process.env.PAIRING_CODE || "654321";
const DEVICE_KEY = process.env.DEVICE_KEY;
const OWNER_EMAIL = process.env.OWNER_EMAIL;
const OWNER_PASS = process.env.OWNER_PASS;
const INGEST = process.env.ENDPOINT ||
  `https://europe-west1-${PROJECT}.cloudfunctions.net/ingestTelemetry`;

const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const IDT = "https://identitytoolkit.googleapis.com/v1/accounts";

// The API key is restricted to the iOS app, so requests carry its bundle id,
// exactly as the app does.
const BUNDLE_ID = process.env.BUNDLE_ID || "com.danielbalicevic.safetrack";
const IOS_HEADERS = { "Content-Type": "application/json", "X-Ios-Bundle-Identifier": BUNDLE_ID };

if (!WEB_KEY || !OWNER_EMAIL || !OWNER_PASS || !DEVICE_KEY) {
  console.error("Set WEB_API_KEY, OWNER_EMAIL, OWNER_PASS and DEVICE_KEY.");
  process.exit(1);
}

const results = [];
function check(name, expected, status, detail, ok) {
  results.push({ name, expected, ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}: HTTP ${status}${detail ? ` (${detail})` : ""}`);
}

async function json(url, opts) {
  const res = await fetch(url, opts);
  let body = {};
  try { body = JSON.parse(await res.text()); } catch (_) {}
  return { status: res.status, body };
}

function reason(body) {
  const m = body && body.error && body.error.message;
  return m ? m.slice(0, 60) : "";
}

const auth = (token) => ({ Authorization: "Bearer " + token, "Content-Type": "application/json" });

async function main() {
  const owner = await json(`${IDT}:signInWithPassword?key=${WEB_KEY}`, {
    method: "POST", headers: IOS_HEADERS,
    body: JSON.stringify({ email: OWNER_EMAIL, password: OWNER_PASS, returnSecureToken: true }),
  });
  if (owner.status !== 200) { console.error("Owner sign-in failed:", reason(owner.body)); process.exit(1); }
  const OWNER_TOKEN = owner.body.idToken;

  const other = await json(`${IDT}:signUp?key=${WEB_KEY}`, {
    method: "POST", headers: IOS_HEADERS,
    body: JSON.stringify({
      email: `security-${Date.now()}@safetrack.invalid`,
      password: "Sec!" + Math.random().toString(36).slice(2, 12),
      returnSecureToken: true,
    }),
  });
  if (other.status !== 200) { console.error("Could not create the test account:", reason(other.body)); process.exit(1); }
  const OTHER_TOKEN = other.body.idToken;
  const OTHER_UID = other.body.localId;

  let r = await json(`${FS}/devices/${DEVICE}`);
  check("Unauthenticated Firestore read", "denied", r.status, reason(r.body), r.status === 401 || r.status === 403);

  r = await json(`${FS}/devices/${DEVICE}`, { headers: auth(OTHER_TOKEN) });
  check("Reading another caregiver's device", "denied", r.status, reason(r.body), r.status === 403);

  r = await json(`${FS}/devices/${DEVICE}`, { headers: auth(OWNER_TOKEN) });
  check("Owner reads their own device", "allowed", r.status, reason(r.body), r.status === 200);

  r = await json(`${FS}/devices/${DEVICE}/telemetry?documentId=security-test`, {
    method: "POST", headers: auth(OWNER_TOKEN),
    body: JSON.stringify({ fields: { battery: { integerValue: "1" } } }),
  });
  check("Client writes telemetry directly", "denied", r.status, reason(r.body), r.status === 403);

  r = await json(`${FS}/alerts?documentId=security-test`, {
    method: "POST", headers: auth(OWNER_TOKEN),
    body: JSON.stringify({ fields: { deviceId: { stringValue: DEVICE }, type: { stringValue: "forged" } } }),
  });
  check("Client creates an alert directly", "denied", r.status, reason(r.body), r.status === 403);

  r = await json(INGEST, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
  check("Ingest without a device key", "401", r.status, "", r.status === 401);

  r = await json(INGEST, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Device-Key": "wrong-key" },
    body: JSON.stringify({ deviceId: DEVICE, lat: 37.1, lng: -8.2, battery: 50, source: "gps", timestamp: Date.now() }),
  });
  check("Ingest with an invalid key", "401", r.status, "", r.status === 401);

  r = await json(INGEST, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Device-Key": DEVICE_KEY },
    body: JSON.stringify({ deviceId: SIM, lat: 37.0998678, lng: -8.2281563, battery: 77, source: "gps", timestamp: Date.now() }),
  });
  check("Ingest with a valid key", "200", r.status, "", r.status === 200);

  const claim = (code, token) => json(
    `${FS}/devices/${SIM}?updateMask.fieldPaths=ownerId&updateMask.fieldPaths=pairingCode`,
    { method: "PATCH", headers: auth(token),
      body: JSON.stringify({ fields: { ownerId: { stringValue: OTHER_UID }, pairingCode: { stringValue: code } } }) });

  r = await claim("000000", OTHER_TOKEN);
  check("Claiming a device with the wrong code", "denied", r.status, reason(r.body), r.status === 403);

  r = await claim(PAIRING_CODE, OTHER_TOKEN);
  const claimed = r.status === 200;
  check("Claiming a device with the correct code", "allowed", r.status, reason(r.body), claimed);

  r = await json(INGEST, { method: "GET" });
  check("Ingest with GET", "405", r.status, "", r.status === 405);

  if (claimed) {
    await json(`${FS}/devices/${SIM}?updateMask.fieldPaths=ownerId`, {
      method: "PATCH", headers: auth(OTHER_TOKEN),
      body: JSON.stringify({ fields: { ownerId: { stringValue: "" } } }),
    });
  }
  await json(`${IDT}:delete?key=${WEB_KEY}`, {
    method: "POST", headers: IOS_HEADERS,
    body: JSON.stringify({ idToken: OTHER_TOKEN }),
  });

  const failed = results.filter((x) => !x.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed.`);
  if (failed.length) console.log("Failed: " + failed.map((f) => f.name).join("; "));
}

main().catch((e) => { console.error(e); process.exit(1); });
