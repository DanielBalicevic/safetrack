# SafeTrack Cloud Functions

Firebase backend (Node.js, `firebase-functions` v2, region `europe-west1`).

## Functions

| Function | Trigger | Description |
| --- | --- | --- |
| `ingestTelemetry` | HTTP | Validates the `X-Device-Key` header and payload, resolves Wi-Fi scans to a position, stores the point and updates `batteryLevel` / `lastSeen`. |
| `processTelemetry` | Firestore `onDocumentCreated` | Evaluates the device's zones and battery level, creates or resolves alerts and sends notifications. |
| `checkDeviceHealth` | Scheduled, every 5 min | Raises an `offline` alert for devices that stopped reporting. |

## Setup

```bash
npm install -g firebase-tools
firebase login
cd functions && npm install
cp .env.example .env   # set DEVICE_KEY, e.g. openssl rand -hex 32
```

Set your project ID in `.firebaserc`. The same `DEVICE_KEY` must be used by the
firmware and the simulator. To configure Telegram notifications:

```bash
node tools/telegram-setup.js <BOT_TOKEN>
```

## Running locally

```bash
firebase emulators:start --only functions,firestore,auth
```

The endpoint is available at
`http://127.0.0.1:5001/<PROJECT_ID>/europe-west1/ingestTelemetry`.
FCM push is not delivered from the emulator.

## Deploy

```bash
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only functions
```

## Tests

```bash
npm test                   # unit tests, no emulator needed
npm run test:integration   # processTelemetry against the Firestore emulator
```

See [test/integration/README.md](test/integration/README.md) for the
integration test requirements.
