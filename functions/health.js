// Device health rules: prolonged silence and low battery. Pure functions, no I/O.

// The firmware reports every 20-30 s, so 15 minutes is roughly 30 missed
// cycles. Short gaps (a tunnel, an elevator) must not wake the caregiver up.
const OFFLINE_AFTER_MS = 15 * 60 * 1000;

// Hysteresis band: alert at 20%, re-arm above 30%. Battery readings fluctuate
// a few percent while the modem transmits.
const LOW_BATTERY_PCT = 20;
const BATTERY_RECOVERED_PCT = 30;

// action: "offline_alert" | "offline_recovered" | "none"
function evaluateOffline(state, nowMs) {
  const lastSeenMs = state.lastSeenMs;
  const alertActive = state.offlineAlertActive === true;

  // A device that never reported cannot be silent.
  if (typeof lastSeenMs !== "number" || !Number.isFinite(lastSeenMs)) {
    return { action: "none", silentMs: 0, updates: {} };
  }

  const silentMs = Math.max(0, nowMs - lastSeenMs);

  if (silentMs >= OFFLINE_AFTER_MS) {
    if (alertActive) return { action: "none", silentMs, updates: {} };
    return { action: "offline_alert", silentMs, updates: { offlineAlertActive: true } };
  }

  if (alertActive) {
    return { action: "offline_recovered", silentMs, updates: { offlineAlertActive: false } };
  }
  return { action: "none", silentMs, updates: {} };
}

// action: "low_battery_alert" | "battery_recovered" | "none"
function evaluateBattery(state) {
  const battery = state.battery;
  const alertActive = state.lowBatteryAlertActive === true;

  if (typeof battery !== "number" || !Number.isFinite(battery)) {
    return { action: "none", updates: {} };
  }

  if (battery <= LOW_BATTERY_PCT && !alertActive) {
    return { action: "low_battery_alert", updates: { lowBatteryAlertActive: true } };
  }
  if (battery >= BATTERY_RECOVERED_PCT && alertActive) {
    return { action: "battery_recovered", updates: { lowBatteryAlertActive: false } };
  }
  return { action: "none", updates: {} };
}

// "2h05" or "18 min"
function formatSilence(ms) {
  const totalMin = Math.floor(ms / 60000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  return h > 0 ? `${h}h${String(m).padStart(2, "0")}` : `${m} min`;
}

module.exports = {
  OFFLINE_AFTER_MS,
  LOW_BATTERY_PCT,
  BATTERY_RECOVERED_PCT,
  evaluateOffline,
  evaluateBattery,
  formatSilence,
};
