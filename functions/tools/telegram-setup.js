#!/usr/bin/env node
// Telegram bot setup: finds your chat id, saves it to functions/.env and sends
// a test message.
//
// Usage:
//   cd functions
//   node tools/telegram-setup.js <TOKEN>   # find the chat id and save it
//   node tools/telegram-setup.js --test    # send a test message using .env

const fs = require("node:fs");
const path = require("node:path");

const ENV_PATH = path.join(__dirname, "..", ".env");

function readEnv() {
  if (!fs.existsSync(ENV_PATH)) return {};
  const out = {};
  for (const line of fs.readFileSync(ENV_PATH, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

function writeEnvValue(key, value) {
  let text = fs.existsSync(ENV_PATH) ? fs.readFileSync(ENV_PATH, "utf8") : "";
  const re = new RegExp(`^\\s*${key}\\s*=.*$`, "m");
  if (re.test(text)) {
    text = text.replace(re, `${key}=${value}`);
  } else {
    if (text.length && !text.endsWith("\n")) text += "\n";
    text += `${key}=${value}\n`;
  }
  fs.writeFileSync(ENV_PATH, text);
}

async function api(token, method, body) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  const data = await res.json();
  if (!data.ok) throw new Error(`${method}: ${data.description || res.status}`);
  return data.result;
}

async function findChats(token) {
  const updates = await api(token, "getUpdates", {});
  const chats = new Map();
  for (const u of updates) {
    const msg = u.message || u.edited_message || u.channel_post;
    if (!msg || !msg.chat) continue;
    const c = msg.chat;
    const name = [c.first_name, c.last_name].filter(Boolean).join(" ") ||
      c.title || c.username || "(unnamed)";
    chats.set(c.id, name);
  }
  return chats;
}

async function sendTest(token, chatId) {
  await api(token, "sendMessage", {
    chat_id: chatId,
    text: "<b>SafeTrack</b>: alert channel connected.",
    parse_mode: "HTML",
  });
  await api(token, "sendLocation", { chat_id: chatId, latitude: 38.6916, longitude: -9.2160 });
}

async function main() {
  const args = process.argv.slice(2);
  const env = readEnv();
  const testOnly = args.includes("--test");
  const token = args.find((a) => !a.startsWith("--")) || env.TELEGRAM_BOT_TOKEN;

  if (!token) {
    console.error("Missing bot token. Usage: node tools/telegram-setup.js <TOKEN>");
    process.exit(1);
  }

  let bot;
  try {
    bot = await api(token, "getMe");
  } catch (err) {
    console.error(`Invalid token or no network: ${err.message}`);
    process.exit(1);
  }
  console.log(`Bot: @${bot.username}`);

  if (testOnly) {
    const chatId = env.TELEGRAM_CHAT_ID;
    if (!chatId) {
      console.error("TELEGRAM_CHAT_ID is not set in .env. Run without --test first.");
      process.exit(1);
    }
    await sendTest(token, chatId);
    console.log(`Test message sent to chat ${chatId}.`);
    return;
  }

  const chats = await findChats(token);
  if (chats.size === 0) {
    console.error(`The bot has not received any messages yet. Send a message to @${bot.username} and try again.`);
    process.exit(1);
  }

  if (chats.size > 1) {
    console.log("Found several chats:");
    for (const [id, name] of chats) console.log(`  ${id}  ${name}`);
    console.log("Saving the first one; edit .env if that is wrong.");
  }

  const [chatId, name] = [...chats][0];
  writeEnvValue("TELEGRAM_BOT_TOKEN", token);
  writeEnvValue("TELEGRAM_CHAT_ID", String(chatId));
  console.log(`Chat: ${chatId} (${name}), saved to ${ENV_PATH}`);

  await sendTest(token, chatId);
  console.log("Test message sent.");
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
