# SafeTrack simulator

Node.js scripts that act as the tracker so the backend can be tested without
hardware. Requires Node 18+.

## Device simulator

```bash
DEVICE_KEY=<key> node simulate.js --inside    # stays inside the zone
DEVICE_KEY=<key> node simulate.js --escape    # leaves the zone (alert)
DEVICE_KEY=<key> node simulate.js --return    # leaves and returns (alert, then resolved)
DEVICE_KEY=<key> node simulate.js --indoor    # sends a Wi-Fi scan instead of GPS
```

Add `--once` to send a single point. Other variables: `ENDPOINT`, `DEVICE_ID`
and `WIFI_APS` (`mac@rssi,mac@rssi`). `DEVICE_KEY` must match
`functions/.env`, and the device must exist in Firestore with at least one
active zone.

## Test scripts

The scripts that use the Admin SDK need a service account key
(`GOOGLE_APPLICATION_CREDENTIALS=./sa-key.json`, never committed).

| Script | Purpose |
| --- | --- |
| `seed-devices.js` | Creates (or removes with `--clean`) synthetic devices `sim-01..sim-NN`. |
| `load-test.js` | Parallel load test; prints latency statistics and writes a CSV. |
| `scenarios-test.js` | Alert lifecycle tests: geofence exit, battery, offline, bad input. |
| `offline-test.js` | Offline alert detection and recovery. |
| `security-test.js` | Firestore rules and ingest authentication, as an untrusted client. |
| `pairing-test.js` | Device pairing rules. |
