#!/usr/bin/env node
// Summarizes the energy log written by the firmware to /log/energy.csv on the
// MicroSD card and estimates battery life from the observed discharge rate.
//
// Usage: node firmware/tools/analyze-energy-log.js <path/to/energy.csv>
//
// For a meaningful result, run the device on battery only (USB powers the
// board) from a full charge.
const fs = require("fs");
const path = require("path");

const REQUIRED = ["epochMs", "bootCount", "activeMs", "batteryMv", "batteryPct", "fixValid", "source", "sent"];

function pct(n, total) {
  return total === 0 ? "0%" : `${((n / total) * 100).toFixed(0)}%`;
}

function main() {
  const file = process.argv[2];
  if (!file) {
    console.error("Usage: node analyze-energy-log.js <path/to/energy.csv>");
    process.exit(1);
  }
  const csv = fs.readFileSync(path.resolve(file), "utf8");
  const lines = csv.split(/\r?\n/).filter((l) => l.trim().length > 0);
  if (lines.length < 2) {
    console.error("The CSV has no data rows.");
    process.exit(1);
  }

  const header = lines[0].split(",");
  const idx = Object.fromEntries(header.map((h, i) => [h.trim(), i]));
  for (const col of REQUIRED) {
    if (!(col in idx)) {
      console.error(`Missing column "${col}".`);
      process.exit(1);
    }
  }

  const rows = lines.slice(1).map((line) => {
    const c = line.split(",");
    return {
      epochMs: Number(c[idx.epochMs]),
      activeMs: Number(c[idx.activeMs]),
      batteryMv: Number(c[idx.batteryMv]),
      batteryPct: Number(c[idx.batteryPct]),
      fixValid: c[idx.fixValid] === "1",
      source: c[idx.source],
      sent: c[idx.sent] === "1",
    };
  });

  const total = rows.length;
  const timed = rows.filter((r) => r.epochMs > 0).sort((a, b) => a.epochMs - b.epochMs);
  const gps = rows.filter((r) => r.fixValid).length;
  const wifi = rows.filter((r) => !r.fixValid && r.source === "wifi").length;
  const sent = rows.filter((r) => r.sent).length;
  const avgActiveMs = rows.reduce((s, r) => s + r.activeMs, 0) / total;

  console.log(`\nSafeTrack energy log: ${file}\n`);
  console.log(`Cycles:              ${total}`);
  console.log(`GPS fix:             ${gps} (${pct(gps, total)})`);
  console.log(`Wi-Fi only:          ${wifi} (${pct(wifi, total)})`);
  console.log(`Sent successfully:   ${sent} (${pct(sent, total)})`);
  console.log(`Average active time: ${avgActiveMs.toFixed(0)} ms`);

  if (timed.length < 2) {
    console.log("\nFewer than two rows have a timestamp; cannot compute a discharge rate.");
    return;
  }

  const first = timed[0];
  const last = timed[timed.length - 1];
  const hours = (last.epochMs - first.epochMs) / 3600000;
  const dropPct = first.batteryPct - last.batteryPct;
  const dropMv = first.batteryMv - last.batteryMv;

  console.log(`\nStart:    ${new Date(first.epochMs).toISOString()}  ${first.batteryPct}% (${first.batteryMv} mV)`);
  console.log(`End:      ${new Date(last.epochMs).toISOString()}  ${last.batteryPct}% (${last.batteryMv} mV)`);
  console.log(`Duration: ${hours.toFixed(2)} h, drop ${dropPct} pp (${dropMv} mV)`);

  if (dropPct <= 0 || hours <= 0) {
    console.log("\nNo battery drop in this window (charging, or the window is too short).");
    return;
  }

  const ratePerHour = dropPct / hours;
  const lifeHours = 100 / ratePerHour;
  console.log(`\nDischarge rate:       ${ratePerHour.toFixed(3)} %/h`);
  console.log(`Estimated battery life: ${lifeHours.toFixed(1)} h (~${(lifeHours / 24).toFixed(1)} days)`);
  console.log("Linear extrapolation; Li-ion discharge is not linear, so measure a full 100% to 0% run for accuracy.");
}

main();
