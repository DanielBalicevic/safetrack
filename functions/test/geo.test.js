const test = require("node:test");
const assert = require("node:assert");
const {
  pointInPolygon,
  haversineMeters,
  centroid,
  evaluateGeofence,
} = require("../geo");

// Square around Lisbon: lat 38.70..38.75, lng -9.15..-9.10
const square = [
  { lat: 38.70, lng: -9.15 },
  { lat: 38.70, lng: -9.10 },
  { lat: 38.75, lng: -9.10 },
  { lat: 38.75, lng: -9.15 },
];

test("point clearly inside", () => {
  assert.strictEqual(pointInPolygon(38.72, -9.12, square), true);
});

test("point clearly outside", () => {
  assert.strictEqual(pointInPolygon(38.80, -9.12, square), false);
  assert.strictEqual(pointInPolygon(38.72, -9.00, square), false);
});

test("points just inside and just outside an edge", () => {
  assert.strictEqual(pointInPolygon(38.7001, -9.12, square), true);
  assert.strictEqual(pointInPolygon(38.6999, -9.12, square), false);
});

test("degenerate polygon never contains a point", () => {
  assert.strictEqual(pointInPolygon(38.72, -9.12, [{ lat: 38.7, lng: -9.1 }]), false);
});

test("haversine matches a known distance (~1.1 km per 0.01 deg of latitude)", () => {
  const d = haversineMeters(38.70, -9.10, 38.71, -9.10);
  assert.ok(d > 1050 && d < 1150, `expected ~1.1 km, got ${d}`);
});

test("centroid of a square", () => {
  const c = centroid(square);
  assert.ok(Math.abs(c.lat - 38.725) < 1e-9);
  assert.ok(Math.abs(c.lng - -9.125) < 1e-9);
});

const home = { name: "Home", type: "circle", active: true, center: { lat: 38.72, lng: -9.12 }, radius: 150, vertices: [] };
const school = { name: "School", type: "polygon", active: true, center: { lat: 0, lng: 0 }, radius: 0, vertices: square };
const inSchool = [38.72, -9.13];
const outsideAll = [38.80, -9.12];

test("inside one of two zones is safe", () => {
  const r = evaluateGeofence([home, school], inSchool[0], inSchool[1], { alertActive: false, outsideCount: 0 });
  assert.strictEqual(r.action, "inside");
  assert.strictEqual(r.insideZone.name, "School");
  assert.strictEqual(r.updates.outsideCount, 0);
});

test("first reading outside does not alert", () => {
  const r = evaluateGeofence([home, school], outsideAll[0], outsideAll[1], { alertActive: false, outsideCount: 0 });
  assert.strictEqual(r.action, "outside_wait");
  assert.strictEqual(r.updates.outsideCount, 1);
});

test("second consecutive reading outside alerts with the last zone name", () => {
  const r = evaluateGeofence([home, school], outsideAll[0], outsideAll[1], { alertActive: false, outsideCount: 1, lastInsideZoneName: "Home" });
  assert.strictEqual(r.action, "outside_alert");
  assert.strictEqual(r.zoneName, "Home");
  assert.strictEqual(r.updates.alertActive, true);
  assert.strictEqual(r.updates.outsideCount, 2);
});

test("entering a zone resets the counter and resolves the alert", () => {
  const r = evaluateGeofence([home, school], inSchool[0], inSchool[1], { alertActive: true, outsideCount: 2, lastInsideZoneName: "Home" });
  assert.strictEqual(r.action, "inside");
  assert.strictEqual(r.resolve, true);
  assert.strictEqual(r.updates.outsideCount, 0);
  assert.strictEqual(r.updates.alertActive, false);
  assert.strictEqual(r.updates.lastInsideZoneName, "School");
});

test("already outside with an open alert does not alert again", () => {
  const r = evaluateGeofence([home, school], outsideAll[0], outsideAll[1], { alertActive: true, outsideCount: 2 });
  assert.strictEqual(r.action, "outside_already");
  assert.strictEqual(r.updates.outsideCount, 3);
});

test("no active zones means no evaluation", () => {
  const none = evaluateGeofence([], outsideAll[0], outsideAll[1], { alertActive: false, outsideCount: 5 });
  assert.strictEqual(none.action, "no_zones");
  assert.strictEqual(none.updates.outsideCount, 0);
  const inactive = evaluateGeofence([{ ...home, active: false }], outsideAll[0], outsideAll[1], { alertActive: false, outsideCount: 0 });
  assert.strictEqual(inactive.action, "no_zones");
});

test("zone name falls back to the nearest zone", () => {
  const r = evaluateGeofence([home, school], outsideAll[0], outsideAll[1], { alertActive: false, outsideCount: 1, lastInsideZoneName: null });
  assert.strictEqual(r.action, "outside_alert");
  assert.ok(r.zoneName === "Home" || r.zoneName === "School");
});
