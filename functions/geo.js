// Geofencing geometry and decision logic. Pure functions, no I/O.
// The inside/outside rules must match the app (lib/services/geo_utils.dart
// and lib/models/zone.dart).

const EARTH_RADIUS_M = 6371000;
const toRad = (deg) => (deg * Math.PI) / 180;

function haversineMeters(lat1, lng1, lat2, lng2) {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Ray casting. `polygon` is an ordered list of { lat, lng } vertices.
function pointInPolygon(lat, lng, polygon) {
  if (!Array.isArray(polygon) || polygon.length < 3) return false;
  let inside = false;
  const n = polygon.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = polygon[i].lng;
    const yi = polygon[i].lat;
    const xj = polygon[j].lng;
    const yj = polygon[j].lat;
    const intersect =
      (yi > lat) !== (yj > lat) &&
      lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

function centroid(polygon) {
  const n = polygon.length;
  let lat = 0;
  let lng = 0;
  for (const p of polygon) {
    lat += p.lat;
    lng += p.lng;
  }
  return { lat: lat / n, lng: lng / n };
}

function isPolygon(zone) {
  return zone.type === "polygon" && Array.isArray(zone.vertices) && zone.vertices.length >= 3;
}

// Zones have the shape:
//   { name, type: "circle" | "polygon", active, center: {lat, lng}, radius, vertices: [{lat, lng}] }
function zoneContains(zone, lat, lng) {
  if (isPolygon(zone)) return pointInPolygon(lat, lng, zone.vertices);
  const c = zone.center || {};
  return haversineMeters(lat, lng, c.lat, c.lng) <= zone.radius;
}

function firstActiveContaining(zones, lat, lng) {
  for (const z of zones) {
    if (z.active && zoneContains(z, lat, lng)) return z;
  }
  return null;
}

// Distance to the zone's center (or centroid). Used for the alert text.
function zoneDistance(zone, lat, lng) {
  const c = isPolygon(zone) ? centroid(zone.vertices) : zone.center || {};
  return haversineMeters(lat, lng, c.lat, c.lng);
}

// Distance from the point to the zone boundary, 0 when inside. Polygons use a
// local equirectangular projection, which is accurate enough at this scale.
function zoneEdgeDistance(zone, lat, lng) {
  if (zoneContains(zone, lat, lng)) return 0;

  if (isPolygon(zone)) {
    const cosRef = Math.cos(toRad(lat));
    // Project to meters with the point at the origin.
    const proj = (p) => ({
      x: toRad(p.lng - lng) * cosRef * EARTH_RADIUS_M,
      y: toRad(p.lat - lat) * EARTH_RADIUS_M,
    });

    let best = Infinity;
    const n = zone.vertices.length;
    for (let i = 0, j = n - 1; i < n; j = i++) {
      const a = proj(zone.vertices[j]);
      const b = proj(zone.vertices[i]);
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len2 = dx * dx + dy * dy;
      const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, -(a.x * dx + a.y * dy) / len2));
      const px = a.x + t * dx;
      const py = a.y + t * dy;
      best = Math.min(best, Math.sqrt(px * px + py * py));
    }
    return best;
  }

  const c = zone.center || {};
  return Math.max(0, haversineMeters(lat, lng, c.lat, c.lng) - zone.radius);
}

function nearestActive(zones, lat, lng) {
  let best = null;
  let bestD = Infinity;
  for (const z of zones) {
    if (!z.active) continue;
    const d = zoneDistance(z, lat, lng);
    if (d < bestD) {
      bestD = d;
      best = z;
    }
  }
  return best;
}

// The device is safe while inside at least one active zone. An alert is
// raised on the second consecutive reading outside all zones, so a single
// bad fix does not trigger it. `accuracy` is the position uncertainty in
// meters (0 for GPS, tens of meters for Wi-Fi).
function evaluateGeofence(zones, lat, lng, state, accuracy = 0) {
  const active = zones.filter((z) => z.active);

  if (active.length === 0) {
    return { action: "no_zones", updates: { outsideCount: 0 } };
  }

  const inside = firstActiveContaining(active, lat, lng);
  if (inside) {
    const updates = { outsideCount: 0, lastInsideZoneName: inside.name };
    const resolve = state.alertActive === true;
    if (resolve) updates.alertActive = false;
    return { action: "inside", insideZone: inside, resolve, updates };
  }

  // If the uncertainty circle still reaches the nearest zone, the reading is
  // inconclusive and is ignored.
  if (accuracy > 0) {
    const nearest = nearestActive(active, lat, lng);
    if (nearest && zoneEdgeDistance(nearest, lat, lng) <= accuracy) {
      return { action: "uncertain", updates: {} };
    }
  }

  const newCount = (state.outsideCount || 0) + 1;

  if (state.alertActive === true) {
    return { action: "outside_already", updates: { outsideCount: newCount } };
  }
  if (newCount < 2) {
    return { action: "outside_wait", updates: { outsideCount: newCount } };
  }

  // Name the zone the device left; fall back to the nearest one.
  const nearest = nearestActive(active, lat, lng);
  const zoneName = state.lastInsideZoneName || (nearest && nearest.name) || "safe zone";
  const distance = nearest ? Math.round(zoneDistance(nearest, lat, lng)) : 0;
  return {
    action: "outside_alert",
    zoneName,
    distance,
    updates: { alertActive: true, outsideCount: newCount },
  };
}

module.exports = {
  haversineMeters,
  pointInPolygon,
  centroid,
  zoneContains,
  firstActiveContaining,
  zoneDistance,
  zoneEdgeDistance,
  nearestActive,
  evaluateGeofence,
};
