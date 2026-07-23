// Telegram notifications, sent alongside FCM.
//
// Native iOS push through FCM requires an APNs key, which needs a paid Apple
// Developer account. A Telegram bot delivers real push notifications to the
// phone at no cost.
//
// Configuration (functions/.env):
//   TELEGRAM_BOT_TOKEN  bot token from @BotFather
//   TELEGRAM_CHAT_ID    default chat; users/{uid}.telegramChatId takes precedence

const logger = require("firebase-functions/logger");

const API = "https://api.telegram.org/bot";
const TIMEOUT_MS = 5000;

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function mapsLink(lat, lng) {
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
}

// Never throws: a Telegram failure must not break the trigger.
async function call(token, method, body) {
  try {
    const res = await fetch(`${API}${token}/${method}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) {
      logger.error(`Telegram ${method} failed (${res.status}): ${await res.text()}`);
      return false;
    }
    return true;
  } catch (err) {
    logger.error(`Telegram ${method} failed:`, err);
    return false;
  }
}

function resolveChatId(userData) {
  return (userData && userData.telegramChatId) || process.env.TELEGRAM_CHAT_ID || null;
}

function getTarget(userData) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = resolveChatId(userData);
  if (!token || !chatId) {
    logger.warn("Telegram not configured (missing TELEGRAM_BOT_TOKEN or chat id).");
    return null;
  }
  return { token, chatId };
}

async function sendText({ userData, text }) {
  const target = getTarget(userData);
  if (!target) return false;
  return call(target.token, "sendMessage", {
    chat_id: target.chatId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
  });
}

async function sendLocation(userData, lat, lng) {
  const target = getTarget(userData);
  if (!target) return false;
  return call(target.token, "sendLocation", {
    chat_id: target.chatId,
    latitude: lat,
    longitude: lng,
  });
}

// Sends the alert text followed by a map pin.
async function sendExitAlert({ userData, deviceName, zoneName, distance, lat, lng }) {
  const text =
    `<b>SafeTrack alert</b>\n\n` +
    `<b>${escapeHtml(deviceName)}</b> left <b>${escapeHtml(zoneName)}</b>.\n` +
    `${Math.round(distance)} m from the zone.\n\n` +
    `<a href="${mapsLink(lat, lng)}">Open in Google Maps</a>`;

  const ok = await sendText({ userData, text });
  if (ok) await sendLocation(userData, lat, lng);
  return ok;
}

async function sendReturnNotice({ userData, deviceName, zoneName }) {
  const zone = zoneName ? ` (<b>${escapeHtml(zoneName)}</b>)` : "";
  return sendText({
    userData,
    text: `<b>${escapeHtml(deviceName)}</b> is back inside a safe zone${zone}.`,
  });
}

async function sendOfflineAlert({ userData, deviceName, silentFor, lat, lng, lastSeenText }) {
  const hasPosition = typeof lat === "number" && typeof lng === "number";
  const lines = [
    `<b>SafeTrack: device offline</b>`,
    ``,
    `<b>${escapeHtml(deviceName)}</b> has not reported for <b>${escapeHtml(silentFor)}</b>.`,
    `Last seen: ${lastSeenText ? escapeHtml(lastSeenText) : "unknown"}.`,
  ];
  if (hasPosition) {
    lines.push(``, `<a href="${mapsLink(lat, lng)}">Open last known position in Google Maps</a>`);
  }
  lines.push(``, `<i>Possible causes: battery depleted, no network or switched off.</i>`);

  const ok = await sendText({ userData, text: lines.join("\n") });
  if (ok && hasPosition) await sendLocation(userData, lat, lng);
  return ok;
}

async function sendOfflineRecovered({ userData, deviceName }) {
  return sendText({
    userData,
    text: `<b>${escapeHtml(deviceName)}</b> is reporting again.`,
  });
}

async function sendLowBatteryAlert({ userData, deviceName, battery }) {
  return sendText({
    userData,
    text:
      `<b>SafeTrack: low battery</b>\n\n` +
      `<b>${escapeHtml(deviceName)}</b> is at <b>${battery}%</b>.\n` +
      `<i>Tracking stops when the battery runs out.</i>`,
  });
}

async function sendBatteryRecovered({ userData, deviceName, battery }) {
  return sendText({
    userData,
    text: `<b>${escapeHtml(deviceName)}</b> is charging (${battery}%).`,
  });
}

module.exports = {
  sendExitAlert,
  sendReturnNotice,
  sendOfflineAlert,
  sendOfflineRecovered,
  sendLowBatteryAlert,
  sendBatteryRecovered,
};
