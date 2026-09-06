// Wi-Fi positioning input handling and accuracy-aware geofencing.
const test = require("node:test");
const assert = require("node:assert");

const { zoneEdgeDistance, evaluateGeofence } = require("../geo");
const { normalizeAccessPoints, MIN_APS } = require("../geolocate");

const CIRCLE = {
  name: "Home",
  type: "circle",
  active: true,
  center: { lat: 38.7223, lng: -9.1393 },
  radius: 100,
};

// Roughly 1.1 km square.
const POLYGON = {
  name: "Neighbourhood",
  type: "polygon",
  active: true,
  vertices: [
    { lat: 38.70, lng: -9.15 },
    { lat: 38.71, lng: -9.15 },
    { lat: 38.71, lng: -9.14 },
    { lat: 38.70, lng: -9.14 },
  ],
};

test("edge distance is 0 inside a circle", () => {
  assert.strictEqual(zoneEdgeDistance(CIRCLE, 38.7223, -9.1393), 0);
});

test("edge distance outside a circle subtracts the radius", () => {
  // ~300 m from the center with a 100 m radius.
  const d = zoneEdgeDistance(CIRCLE, 38.7223 + 0.0027, -9.1393);
  assert.ok(d > 150 && d < 250, `expected ~200 m, got ${d}`);
});

test("edge distance is 0 inside a polygon", () => {
  assert.strictEqual(zoneEdgeDistance(POLYGON, 38.705, -9.145), 0);
});

test("edge distance outside a polygon is measured to the nearest edge", () => {
  // ~110 m above the top edge; the centroid is ~660 m away.
  const d = zoneEdgeDistance(POLYGON, 38.711, -9.145);
  assert.ok(d > 80 && d < 140, `expected ~110 m, got ${d}`);
});

const CLEAN = { alertActive: false, outsideCount: 0, lastInsideZoneName: "Home" };

test("a GPS fix 200 m outside counts towards the debounce", () => {
  const r = evaluateGeofence([CIRCLE], 38.7223 + 0.0027, -9.1393, CLEAN, 0);
  assert.strictEqual(r.action, "outside_wait");
});

test("an imprecise fix that still reaches the zone is inconclusive", () => {
  const r = evaluateGeofence([CIRCLE], 38.7223 + 0.0027, -9.1393, CLEAN, 250);
  assert.strictEqual(r.action, "uncertain");
  assert.deepStrictEqual(r.updates, {});
});

test("an imprecise fix does not resolve an open alert", () => {
  const withAlert = { alertActive: true, outsideCount: 2, lastInsideZoneName: "Home" };
  const r = evaluateGeofence([CIRCLE], 38.7223 + 0.0027, -9.1393, withAlert, 250);
  assert.strictEqual(r.action, "uncertain");
});

test("a Wi-Fi fix far enough away still alerts", () => {
  const state = { alertActive: false, outsideCount: 1, lastInsideZoneName: "Home" };
  const r = evaluateGeofence([CIRCLE], 38.7223 + 0.01, -9.1393, state, 50);
  assert.strictEqual(r.action, "outside_alert");
  assert.strictEqual(r.zoneName, "Home");
});

test("inside the zone is safe regardless of accuracy", () => {
  const r = evaluateGeofence([CIRCLE], 38.7223, -9.1393, CLEAN, 500);
  assert.strictEqual(r.action, "inside");
});

test("valid MAC addresses are accepted and lowercased", () => {
  const aps = normalizeAccessPoints([
    { mac: "AA:BB:CC:DD:EE:FF", rssi: -55 },
    { mac: "00:11:22:33:44:55", rssi: -70 },
  ]);
  assert.strictEqual(aps.length, 2);
  assert.strictEqual(aps[0].macAddress, "aa:bb:cc:dd:ee:ff");
  assert.strictEqual(aps[0].signalStrength, -55);
});

test("malformed MACs and non-numeric RSSI are dropped", () => {
  const aps = normalizeAccessPoints([
    { mac: "not-a-mac", rssi: -55 },
    { mac: "AA:BB:CC:DD:EE:FF", rssi: "strong" },
    { mac: "AA:BB:CC:DD:EE:FF" },
    { mac: "00:11:22:33:44:55", rssi: -70 },
  ]);
  assert.strictEqual(aps.length, 1);
  assert.strictEqual(aps[0].macAddress, "00:11:22:33:44:55");
});

test("non-array or empty input yields an empty list", () => {
  assert.deepStrictEqual(normalizeAccessPoints(undefined), []);
  assert.deepStrictEqual(normalizeAccessPoints("aa:bb"), []);
  assert.deepStrictEqual(normalizeAccessPoints([]), []);
});

test("at least two access points are required", () => {
  assert.ok(MIN_APS >= 2);
});
