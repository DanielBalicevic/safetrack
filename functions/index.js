// SafeTrack Cloud Functions.
//
// ingestTelemetry    HTTP endpoint that receives positions from the device.
// processTelemetry   Firestore trigger that evaluates geofences and device health.
// checkDeviceHealth  Scheduled job that detects devices that stopped reporting.

const { setGlobalOptions } = require("firebase-functions/v2");
const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const { evaluateGeofence } = require("./geo");
const notify = require("./notify");
const { locateByWifi } = require("./geolocate");
const {
  OFFLINE_AFTER_MS,
  evaluateOffline,
  evaluateBattery,
  formatSilence,
} = require("./health");

admin.initializeApp();
const db = admin.firestore();

// Keep data in the EU and close to the users (Portugal).
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

// Converts a Firestore zone document into the plain shape used by geo.js.
function normalizeZone(data, id) {
  const c = data.center;
  return {
    id,
    name: data.name || "Zone",
    type: data.type === "polygon" ? "polygon" : "circle",
    active: data.active === true,
    radius: Number(data.radius) || 0,
    center: c ? { lat: c.latitude, lng: c.longitude } : { lat: 0, lng: 0 },
    vertices: Array.isArray(data.vertices)
      ? data.vertices.map((v) => ({ lat: Number(v.lat), lng: Number(v.lng) }))
      : [],
  };
}

function isNumberInRange(value, min, max) {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max;
}

// POST /ingestTelemetry
//   Header: X-Device-Key: <shared key>
//   Body:   { deviceId, battery, lat, lng, timestamp? } or { deviceId, battery, wifi: [...] }
exports.ingestTelemetry = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed. Use POST." });
  }

  const expectedKey = process.env.DEVICE_KEY;
  const providedKey = req.get("X-Device-Key");

  if (!expectedKey) {
    logger.error("DEVICE_KEY is not set in the functions environment.");
    return res.status(500).json({ error: "Server misconfigured." });
  }
  if (!providedKey || providedKey !== expectedKey) {
    logger.warn("Rejected ingest request without a valid device key.");
    return res.status(401).json({ error: "Missing or invalid device key." });
  }

  const body = req.body || {};
  const { deviceId, battery } = body;
  let { lat, lng, timestamp } = body;

  if (typeof deviceId !== "string" || deviceId.trim() === "") {
    return res.status(400).json({ error: "Missing or invalid deviceId." });
  }
  if (!isNumberInRange(battery, 0, 100)) {
    return res.status(400).json({ error: "battery must be within [0, 100]." });
  }

  // Indoors the device sends a Wi-Fi scan instead of coordinates. It is
  // resolved here so the Geolocation API key never has to live on the device.
  let source = "gps";
  let accuracy = 0;
  const hasCoordinates = isNumberInRange(lat, -90, 90) && isNumberInRange(lng, -180, 180);

  if (!hasCoordinates) {
    if (!Array.isArray(body.wifi) || body.wifi.length === 0) {
      return res.status(400).json({ error: "No valid lat/lng and no wifi list." });
    }
    const fix = await locateByWifi(body.wifi);
    if (!fix) {
      return res.status(422).json({ error: "Could not resolve a position from Wi-Fi." });
    }
    lat = fix.lat;
    lng = fix.lng;
    accuracy = fix.accuracy;
    source = "wifi";
  }
  if (typeof timestamp !== "number" || !Number.isFinite(timestamp)) {
    timestamp = Date.now();
  }

  try {
    const deviceRef = db.collection("devices").doc(deviceId);

    // Only provisioned devices may report.
    const deviceSnap = await deviceRef.get();
    if (!deviceSnap.exists) {
      return res.status(404).json({ error: "Unknown device." });
    }

    const pointRef = await deviceRef.collection("telemetry").add({
      lat,
      lng,
      battery,
      timestamp,
      source,
      accuracy,
      receivedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await deviceRef.update({
      batteryLevel: battery,
      lastSeen: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info(`Telemetry accepted for ${deviceId} (point ${pointRef.id}).`);
    return res.status(200).json({ ok: true, pointId: pointRef.id });
  } catch (err) {
    logger.error("Failed to store telemetry:", err);
    return res.status(500).json({ error: "Internal error while storing telemetry." });
  }
});

// Runs for every new telemetry point. One alert is raised per exit and stays
// open until the device is back inside a zone.
exports.processTelemetry = onDocumentCreated(
  "devices/{deviceId}/telemetry/{pointId}",
  async (event) => {
    const deviceId = event.params.deviceId;
    const snap = event.data;
    if (!snap) return;

    const point = snap.data();
    const { lat, lng } = point;

    const zonesSnap = await db
      .collection(`devices/${deviceId}/geofences`)
      .where("active", "==", true)
      .get();
    const zones = zonesSnap.docs.map((d) => normalizeZone(d.data(), d.id));

    const deviceRef = db.doc(`devices/${deviceId}`);
    const deviceSnap = await deviceRef.get();
    const device = deviceSnap.exists ? deviceSnap.data() : {};
    const state = {
      alertActive: device.alertActive === true,
      outsideCount: device.outsideCount || 0,
      lastInsideZoneName: device.lastInsideZoneName || null,
    };

    // Health checks run first because several geofence branches return early.
    await handleDeviceHealth(deviceRef, device, deviceId, point);

    const accuracy = typeof point.accuracy === "number" ? point.accuracy : 0;
    const result = evaluateGeofence(zones, lat, lng, state, accuracy);
    logger.info(
      `${deviceId}: action=${result.action}, activeZones=${zones.length}, ` +
        `source=${point.source || "gps"}, accuracy=${accuracy}m`
    );

    switch (result.action) {
      case "uncertain":
        return;

      case "no_zones":
        if (state.outsideCount !== 0) await deviceRef.update(result.updates);
        return;

      case "inside": {
        await deviceRef.update(result.updates);
        if (result.resolve) {
          logger.info(`${deviceId}: back inside a zone, resolving exit alerts.`);
          // Battery and offline alerts are unrelated to the position.
          await resolveOpenAlerts(deviceId, ["geofence_exit"]);
          await notifyReturn(device, deviceId, result.insideZone && result.insideZone.name);
        }
        return;
      }

      case "outside_wait":
      case "outside_already":
        await deviceRef.update(result.updates);
        return;

      case "outside_alert": {
        logger.info(`${deviceId}: left "${result.zoneName}", raising alert.`);
        await db.collection("alerts").add({
          deviceId,
          type: "geofence_exit",
          zoneName: result.zoneName,
          distance: result.distance,
          radius: 0,
          lat,
          lng,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          resolved: false,
        });
        await deviceRef.update(result.updates);
        await sendGeofenceAlert(device, deviceId, result.zoneName, result.distance, lat, lng);
        return;
      }
    }
  }
);

async function getOwnerData(device, deviceId) {
  const ownerId = device.ownerId;
  if (!ownerId) {
    logger.warn(`${deviceId}: no owner, nobody to notify.`);
    return null;
  }
  const userSnap = await db.doc(`users/${ownerId}`).get();
  return { ownerId, userData: userSnap.exists ? userSnap.data() : {} };
}

function deviceLabel(device) {
  return device.name || "The device";
}

// Push failures are logged and swallowed: the alert is already stored.
async function sendFcm(userData, deviceId, { title, body, data }) {
  try {
    const fcmToken = userData.fcmToken;
    if (!fcmToken) {
      logger.warn(`${deviceId}: owner has no FCM token.`);
      return;
    }

    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      // FCM requires every data value to be a string.
      data: Object.fromEntries(
        Object.entries({ deviceId, ...data }).map(([k, v]) => [k, String(v)])
      ),
    });

    logger.info(`${deviceId}: FCM push sent.`);
  } catch (err) {
    logger.error(`${deviceId}: FCM push failed:`, err);
  }
}

async function sendGeofenceAlert(device, deviceId, zoneName, distance, lat, lng) {
  const owner = await getOwnerData(device, deviceId);
  if (!owner) return;

  const name = deviceLabel(device);
  const [, telegramOk] = await Promise.all([
    sendFcm(owner.userData, deviceId, {
      title: "SafeTrack alert",
      body: `${name} left ${zoneName}.`,
      data: { type: "geofence_exit", zoneName, distance },
    }),
    notify.sendExitAlert({
      userData: owner.userData,
      deviceName: name,
      zoneName,
      distance,
      lat,
      lng,
    }),
  ]);

  logger.info(`${deviceId}: exit alert delivered (telegram=${telegramOk}).`);
}

async function notifyReturn(device, deviceId, zoneName) {
  const owner = await getOwnerData(device, deviceId);
  if (!owner) return;
  await notify.sendReturnNotice({
    userData: owner.userData,
    deviceName: deviceLabel(device),
    zoneName,
  });
}

// Resolves the device's open alerts of the given types. The type filter runs
// in memory to avoid a composite index; open alerts per device are few.
async function resolveOpenAlerts(deviceId, types) {
  const open = await db
    .collection("alerts")
    .where("deviceId", "==", deviceId)
    .where("resolved", "==", false)
    .get();

  // Older alerts have no `type` field and are all geofence exits.
  const matching = open.docs.filter((d) => types.includes(d.data().type || "geofence_exit"));
  if (matching.length === 0) return 0;

  const batch = db.batch();
  matching.forEach((doc) =>
    batch.update(doc.ref, {
      resolved: true,
      resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    })
  );
  await batch.commit();
  return matching.length;
}

// Low battery and recovery from silence, evaluated on every point.
// Never throws, so a failure here cannot block the geofence evaluation.
async function handleDeviceHealth(deviceRef, device, deviceId, point) {
  try {
    const nowMs = Date.now();
    const updates = {};

    // The device has just reported, so it is no longer silent.
    const offline = evaluateOffline(
      { lastSeenMs: nowMs, offlineAlertActive: device.offlineAlertActive },
      nowMs
    );
    if (offline.action === "offline_recovered") {
      logger.info(`${deviceId}: reporting again, resolving offline alert.`);
      Object.assign(updates, offline.updates);
      await resolveOpenAlerts(deviceId, ["offline"]);
      const owner = await getOwnerData(device, deviceId);
      if (owner) {
        await notify.sendOfflineRecovered({
          userData: owner.userData,
          deviceName: deviceLabel(device),
        });
      }
    }

    const battery = evaluateBattery({
      battery: point.battery,
      lowBatteryAlertActive: device.lowBatteryAlertActive,
    });
    Object.assign(updates, battery.updates);

    if (battery.action === "low_battery_alert") {
      logger.info(`${deviceId}: battery at ${point.battery}%, raising alert.`);
      await db.collection("alerts").add({
        deviceId,
        type: "low_battery",
        battery: point.battery,
        lat: point.lat,
        lng: point.lng,
        distance: 0,
        radius: 0,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        resolved: false,
      });
      const owner = await getOwnerData(device, deviceId);
      if (owner) {
        const name = deviceLabel(device);
        await Promise.all([
          sendFcm(owner.userData, deviceId, {
            title: "SafeTrack: low battery",
            body: `${name} is at ${point.battery}%.`,
            data: { type: "low_battery", battery: point.battery },
          }),
          notify.sendLowBatteryAlert({
            userData: owner.userData,
            deviceName: name,
            battery: point.battery,
          }),
        ]);
      }
    } else if (battery.action === "battery_recovered") {
      logger.info(`${deviceId}: battery recovered (${point.battery}%), resolving alert.`);
      await resolveOpenAlerts(deviceId, ["low_battery"]);
      const owner = await getOwnerData(device, deviceId);
      if (owner) {
        await notify.sendBatteryRecovered({
          userData: owner.userData,
          deviceName: deviceLabel(device),
          battery: point.battery,
        });
      }
    }

    if (Object.keys(updates).length > 0) await deviceRef.update(updates);
  } catch (err) {
    logger.error(`${deviceId}: health check failed:`, err);
  }
}

// A silent device produces no events, so only a scheduled job can detect it.
// One query per run, regardless of how many devices are healthy. Recovery is
// handled by processTelemetry as soon as a new point arrives.
exports.checkDeviceHealth = onSchedule(
  { schedule: "every 5 minutes", timeZone: "Europe/Lisbon" },
  async () => {
    const nowMs = Date.now();
    const cutoff = admin.firestore.Timestamp.fromMillis(nowMs - OFFLINE_AFTER_MS);

    const silent = await db.collection("devices").where("lastSeen", "<", cutoff).get();
    logger.info(`Health check: ${silent.size} silent device(s).`);

    for (const doc of silent.docs) {
      const device = doc.data();
      const deviceId = doc.id;

      if (!device.ownerId) continue;

      const lastSeen = device.lastSeen;
      const r = evaluateOffline(
        {
          lastSeenMs: lastSeen && typeof lastSeen.toMillis === "function"
            ? lastSeen.toMillis()
            : null,
          offlineAlertActive: device.offlineAlertActive,
        },
        nowMs
      );
      if (r.action !== "offline_alert") continue;

      const silentFor = formatSilence(r.silentMs);
      logger.warn(`${deviceId}: silent for ${silentFor}, raising alert.`);

      // The last known position is the most useful information left.
      let lat = null;
      let lng = null;
      try {
        const last = await db
          .collection(`devices/${deviceId}/telemetry`)
          .orderBy("timestamp", "desc")
          .limit(1)
          .get();
        if (!last.empty) {
          const p = last.docs[0].data();
          lat = typeof p.lat === "number" ? p.lat : null;
          lng = typeof p.lng === "number" ? p.lng : null;
        }
      } catch (err) {
        logger.error(`${deviceId}: failed to read last position:`, err);
      }

      await db.collection("alerts").add({
        deviceId,
        type: "offline",
        silentMs: r.silentMs,
        lastSeen: lastSeen || null,
        battery: typeof device.batteryLevel === "number" ? device.batteryLevel : null,
        lat: lat ?? 0,
        lng: lng ?? 0,
        distance: 0,
        radius: 0,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        resolved: false,
      });
      await doc.ref.update(r.updates);

      const owner = await getOwnerData(device, deviceId);
      if (!owner) continue;

      const name = deviceLabel(device);
      await Promise.all([
        sendFcm(owner.userData, deviceId, {
          title: "SafeTrack: device offline",
          body: `${name} has not reported for ${silentFor}.`,
          data: { type: "offline", silentMs: r.silentMs },
        }),
        notify.sendOfflineAlert({
          userData: owner.userData,
          deviceName: name,
          silentFor,
          lat,
          lng,
          lastSeenText: lastSeen && typeof lastSeen.toDate === "function"
            ? lastSeen.toDate().toISOString().replace("T", " ").slice(0, 16) + " UTC"
            : null,
        }),
      ]);
    }
  }
);
