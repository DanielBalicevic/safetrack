// Pairing rules tests: claiming a device that does not exist, a device that
// already has an owner, and unpairing then pairing again. Runs as an
// authenticated REST client so the Firestore rules are evaluated for real.
// Creates and deletes its own throwaway account.
//
// Usage: WEB_API_KEY=<firebase web key> node pairing-test.js

const PROJECT = process.env.PROJECT_ID || "safetrack-b46b1";
const WEB_KEY = process.env.WEB_API_KEY;
const BUNDLE = process.env.BUNDLE_ID || "com.danielbalicevic.safetrack";
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const IDT = "https://identitytoolkit.googleapis.com/v1/accounts";

const OWNED_DEVICE = process.env.OWNED_DEVICE || "device-teste-01";
const FREE_DEVICE = process.env.FREE_DEVICE || "sim-02";
const CODE = process.env.PAIRING_CODE || "654321";
const MISSING_DEVICE = "missing-device-" + Date.now();

if (!WEB_KEY) {
  console.error("Set WEB_API_KEY.");
  process.exit(1);
}

const HEADERS = { "Content-Type": "application/json", "X-Ios-Bundle-Identifier": BUNDLE };
const results = [];

async function json(url, opts) {
  const r = await fetch(url, opts);
  let b = {};
  try { b = JSON.parse(await r.text()); } catch (_) {}
  return { status: r.status, body: b };
}

function check(name, actual, ok) {
  results.push({ name, ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}: ${actual}`);
}

(async () => {
  const user = await json(`${IDT}:signUp?key=${WEB_KEY}`, {
    method: "POST", headers: HEADERS,
    body: JSON.stringify({
      email: `pairing-${Date.now()}@safetrack.invalid`,
      password: "Pair!" + Math.random().toString(36).slice(2, 12),
      returnSecureToken: true,
    }),
  });
  if (user.status !== 200) { console.error("Could not create the test account."); process.exit(1); }
  const TOKEN = user.body.idToken;
  const UID = user.body.localId;
  const auth = { Authorization: "Bearer " + TOKEN, "Content-Type": "application/json" };

  const claim = (device, code) => json(
    `${FS}/devices/${device}?updateMask.fieldPaths=ownerId&updateMask.fieldPaths=pairingCode`,
    { method: "PATCH", headers: auth,
      body: JSON.stringify({ fields: { ownerId: { stringValue: UID }, pairingCode: { stringValue: code } } }) });
  const release = (device) => json(`${FS}/devices/${device}?updateMask.fieldPaths=ownerId`, {
    method: "PATCH", headers: auth,
    body: JSON.stringify({ fields: { ownerId: { stringValue: "" } } }),
  });

  let r = await claim(MISSING_DEVICE, CODE);
  check("Claiming a device that does not exist is rejected", `HTTP ${r.status}`, r.status === 403 || r.status === 404);

  r = await claim(OWNED_DEVICE, CODE);
  check("Claiming a device owned by someone else is rejected", `HTTP ${r.status}`, r.status === 403);

  r = await json(`${FS}/devices/${OWNED_DEVICE}`, { headers: auth });
  check("The previous owner is kept", `read HTTP ${r.status}`, r.status === 403);

  const first = await claim(FREE_DEVICE, CODE);
  const released = await release(FREE_DEVICE);
  const second = await claim(FREE_DEVICE, CODE);
  check("Unpairing and pairing again works",
    `claim ${first.status}, release ${released.status}, claim ${second.status}`,
    first.status === 200 && released.status === 200 && second.status === 200);

  await release(FREE_DEVICE);
  await json(`${IDT}:delete?key=${WEB_KEY}`, { method: "POST", headers: HEADERS, body: JSON.stringify({ idToken: TOKEN }) });

  const failed = results.filter((x) => !x.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed.`);
  process.exit(failed.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
