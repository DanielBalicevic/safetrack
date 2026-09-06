# Integration tests

`processTelemetry.integration.js` runs the `processTelemetry` trigger end to
end against the Firestore emulator.

## Requirements

- Java 21 or newer (required by the Firestore emulator).
- `firebase-tools`, logged in.
- Ports 5001 (functions) and 8080 (Firestore) free.

## Running

```bash
cd functions
npm run test:integration
```

`firebase emulators:exec` starts the emulators, runs the tests and shuts them
down.

## Notes

- The file name does not end in `.test.js`, so `npm test` does not pick it up.
  It also refuses to run unless `FIRESTORE_EMULATOR_HOST` is set, so it can
  never touch the production database.
- Test devices have no `ownerId`, so no notifications are sent during the run.
