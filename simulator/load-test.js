// Load test: N devices posting telemetry in parallel at the real reporting
// interval for M minutes. Prints request latency statistics and writes every
// request to a CSV file.
//
// Measures client-side round-trip time. Function execution time is available
// in the Firebase console.
//
// Usage (seed the devices first with seed-devices.js):
//   DEVICE_KEY=<key> node load-test.js --devices=1  --minutes=10
//   DEVICE_KEY=<key> node load-test.js --devices=10 --minutes=30
//
// Options: --devices=N --minutes=M --interval=S --prefix=sim

const fs = require("fs");

const ENDPOINT =
  process.env.ENDPOINT ||
  "https://europe-west1-safetrack-b46b1.cloudfunctions.net/ingestTelemetry";
const DEVICE_KEY = process.env.DEVICE_KEY;

function arg(name, def) {
  const hit = process.argv.slice(2).find((a) => a.startsWith("--" + name + "="));
  return hit ? hit.split("=")[1] : def;
}

const N_DEVICES = parseInt(arg("devices", "10"), 10);
const MINUTES = parseFloat(arg("minutes", "30"));
const INTERVAL_S = parseInt(arg("interval", "20"), 10);
const PREFIX = arg("prefix", "sim");

// Center of the zones created by seed-devices.js. Points stay inside so the
// geometry runs without flooding the system with alerts.
const CENTER_LAT = 37.0998678;
const CENTER_LNG = -8.2281563;
const M_PER_DEG_LAT = 111320;

if (!DEVICE_KEY) {
  console.error("Set DEVICE_KEY (the same value as in functions/.env).");
  process.exit(1);
}

const rows = [];
let sent = 0;
let errors = 0;

function deviceId(i) {
  return PREFIX + "-" + String(i + 1).padStart(2, "0");
}

async function sendOne(i, seq) {
  const id = deviceId(i);
  const meters = 10 + ((seq * 7 + i * 13) % 60);
  const payload = {
    deviceId: id,
    lat: CENTER_LAT + meters / M_PER_DEG_LAT,
    lng: CENTER_LNG,
    battery: Math.max(5, 95 - Math.floor(seq / 4)),
    source: "gps",
    timestamp: Date.now(),
  };

  const t0 = process.hrtime.bigint();
  let status = 0;
  let err = "";
  let body = "";
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Device-Key": DEVICE_KEY },
      body: JSON.stringify(payload),
    });
    status = res.status;
    body = (await res.text()).slice(0, 300);
  } catch (e) {
    err = e.message;
  }
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;

  sent++;
  if (status !== 200) {
    errors++;
    if (errors === 1) {
      console.error(`First failed request: HTTP ${status}${err ? ` (${err})` : ""} ${body}`);
    }
    // Abort early instead of running a long test that records nothing.
    if (sent >= 3 && errors === sent) {
      console.error("The first three requests failed. Aborting.");
      report();
      process.exit(1);
    }
  }
  rows.push({ ts: new Date().toISOString(), device: id, seq, status, ms: ms.toFixed(1), err });
}

function percentile(values, p) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.min(Math.max(idx, 0), sorted.length - 1)];
}

function report() {
  const ok = rows.filter((r) => r.status === 200).map((r) => parseFloat(r.ms));
  const mean = ok.length ? ok.reduce((a, b) => a + b, 0) / ok.length : 0;

  const file = `load-${N_DEVICES}dev-${new Date().toISOString().slice(0, 16).replace(/[:T]/g, "")}.csv`;
  fs.writeFileSync(
    file,
    "timestamp,device,seq,http_status,rtt_ms,error\n" +
      rows.map((r) => [r.ts, r.device, r.seq, r.status, r.ms, r.err].join(",")).join("\n") + "\n"
  );

  console.log(`\nDevices:   ${N_DEVICES}`);
  console.log(`Duration:  ${MINUTES} min at ${INTERVAL_S} s per cycle`);
  console.log(`Requests:  ${sent}`);
  console.log(`Mean RTT:  ${mean.toFixed(0)} ms`);
  console.log(`p95 RTT:   ${percentile(ok, 95).toFixed(0)} ms`);
  console.log(`Errors:    ${errors}`);
  console.log(`CSV:       ${file}`);
}

console.log(`${N_DEVICES} devices, ${MINUTES} min, ${INTERVAL_S} s interval -> ${ENDPOINT}`);
console.log("Ctrl-C stops the test and prints a partial report.\n");

const seqs = new Array(N_DEVICES).fill(0);
const timers = [];

for (let i = 0; i < N_DEVICES; i++) {
  // Spread device start times across the interval.
  const jitter = Math.floor((i / N_DEVICES) * INTERVAL_S * 1000);
  setTimeout(() => {
    sendOne(i, seqs[i]++);
    timers.push(setInterval(() => sendOne(i, seqs[i]++), INTERVAL_S * 1000));
  }, jitter);
}

const end = setTimeout(() => {
  timers.forEach(clearInterval);
  setTimeout(() => { report(); process.exit(0); }, 3000);
}, MINUTES * 60 * 1000);

process.on("SIGINT", () => {
  timers.forEach(clearInterval);
  clearTimeout(end);
  report();
  process.exit(0);
});
