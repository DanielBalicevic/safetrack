const test = require("node:test");
const assert = require("node:assert");
const {
  OFFLINE_AFTER_MS,
  LOW_BATTERY_PCT,
  BATTERY_RECOVERED_PCT,
  evaluateOffline,
  evaluateBattery,
  formatSilence,
} = require("../health");

const NOW = 1_700_000_000_000;
const min = (n) => n * 60 * 1000;

test("a device that never reported does not alert", () => {
  const r = evaluateOffline({ lastSeenMs: null, offlineAlertActive: false }, NOW);
  assert.strictEqual(r.action, "none");
});

test("recently seen device: no action", () => {
  const r = evaluateOffline({ lastSeenMs: NOW - min(2), offlineAlertActive: false }, NOW);
  assert.strictEqual(r.action, "none");
});

test("just below the threshold does not alert", () => {
  const r = evaluateOffline(
    { lastSeenMs: NOW - OFFLINE_AFTER_MS + 1000, offlineAlertActive: false },
    NOW
  );
  assert.strictEqual(r.action, "none");
});

test("past the threshold alerts and sets the flag", () => {
  const r = evaluateOffline(
    { lastSeenMs: NOW - OFFLINE_AFTER_MS - 1000, offlineAlertActive: false },
    NOW
  );
  assert.strictEqual(r.action, "offline_alert");
  assert.strictEqual(r.updates.offlineAlertActive, true);
  assert.ok(r.silentMs >= OFFLINE_AFTER_MS);
});

test("an open offline alert is not repeated", () => {
  const r = evaluateOffline({ lastSeenMs: NOW - min(180), offlineAlertActive: true }, NOW);
  assert.strictEqual(r.action, "none");
  assert.deepStrictEqual(r.updates, {});
});

test("reporting again with an open alert recovers", () => {
  const r = evaluateOffline({ lastSeenMs: NOW, offlineAlertActive: true }, NOW);
  assert.strictEqual(r.action, "offline_recovered");
  assert.strictEqual(r.updates.offlineAlertActive, false);
});

test("reporting without an open alert: no action", () => {
  const r = evaluateOffline({ lastSeenMs: NOW, offlineAlertActive: false }, NOW);
  assert.strictEqual(r.action, "none");
});

test("a device clock ahead of the server never yields negative silence", () => {
  const r = evaluateOffline({ lastSeenMs: NOW + min(5), offlineAlertActive: false }, NOW);
  assert.strictEqual(r.silentMs, 0);
  assert.strictEqual(r.action, "none");
});

test("offline threshold is well above the app's 5 min 'no signal' banner", () => {
  assert.ok(OFFLINE_AFTER_MS > min(5));
});

test("battery at the threshold alerts", () => {
  const r = evaluateBattery({ battery: LOW_BATTERY_PCT, lowBatteryAlertActive: false });
  assert.strictEqual(r.action, "low_battery_alert");
  assert.strictEqual(r.updates.lowBatteryAlertActive, true);
});

test("healthy battery does not alert", () => {
  const r = evaluateBattery({ battery: 80, lowBatteryAlertActive: false });
  assert.strictEqual(r.action, "none");
});

test("low battery with an open alert does not repeat", () => {
  const r = evaluateBattery({ battery: 8, lowBatteryAlertActive: true });
  assert.strictEqual(r.action, "none");
  assert.deepStrictEqual(r.updates, {});
});

test("hysteresis: state is kept between the two thresholds", () => {
  const mid = (LOW_BATTERY_PCT + BATTERY_RECOVERED_PCT) / 2;
  assert.strictEqual(evaluateBattery({ battery: mid, lowBatteryAlertActive: true }).action, "none");
  assert.strictEqual(evaluateBattery({ battery: mid, lowBatteryAlertActive: false }).action, "none");
});

test("above the recovery threshold the alert is resolved", () => {
  const r = evaluateBattery({ battery: BATTERY_RECOVERED_PCT, lowBatteryAlertActive: true });
  assert.strictEqual(r.action, "battery_recovered");
  assert.strictEqual(r.updates.lowBatteryAlertActive, false);
});

test("missing or invalid battery value is ignored", () => {
  assert.strictEqual(evaluateBattery({ lowBatteryAlertActive: false }).action, "none");
  assert.strictEqual(evaluateBattery({ battery: NaN, lowBatteryAlertActive: false }).action, "none");
  assert.strictEqual(evaluateBattery({ battery: "20", lowBatteryAlertActive: false }).action, "none");
});

test("recovery threshold is above the alert threshold", () => {
  assert.ok(BATTERY_RECOVERED_PCT > LOW_BATTERY_PCT);
});

test("formatSilence formats minutes and hours", () => {
  assert.strictEqual(formatSilence(min(18)), "18 min");
  assert.strictEqual(formatSilence(min(125)), "2h05");
});
