const fs = require("fs");
const path = require("path");

const CACHE_DIR = path.join(__dirname, "cache");
const CACHE_TTL = parseInt(process.env.CACHE_TTL_MS || "3600000", 10);

const LOCATIONS = {
  vlissingen: { name: "Vlissingen" },
  yerseke: { name: "Kattendijke" },
};

function fmtAge(ms) {
  const sec = Math.floor(ms / 1000);
  if (sec < 60) return `${sec}s ago`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}m ago`;
  return `${Math.floor(min / 60)}h ${min % 60}m ago`;
}

function readCache(key) {
  const file = path.join(CACHE_DIR, `${key}.json`);
  try {
    const entry = JSON.parse(fs.readFileSync(file, "utf8"));
    return { data: entry.data, ts: entry.ts, stale: Date.now() - entry.ts > CACHE_TTL };
  } catch {
    return null;
  }
}

function pad(n) {
  return String(n).padStart(2, "0");
}

function fmtTime(ts) {
  const d = new Date(ts);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fmtDate(ts) {
  const d = new Date(ts);
  const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

function box(title, lines, width) {
  const bar = "\u2500".repeat(width - 2);
  const out = [];
  out.push(`\u250c\u2500 ${title} ${bar.slice(title.length + 3)}\u2510`);
  for (const line of lines) {
    const padding = width - 2 - stripAnsi(line).length;
    out.push(`\u2502 ${line}${" ".repeat(Math.max(0, padding))}\u2502`);
  }
  out.push(`\u2514${bar}\u2518`);
  return out.join("\n");
}

function stripAnsi(s) {
  return s.replace(/\x1b\[[0-9;]*m/g, "");
}

function center(text, width) {
  const len = stripAnsi(text).length;
  const pad = Math.max(0, Math.floor((width - len) / 2));
  return " ".repeat(pad) + text;
}

function dots(active, total, width) {
  let s = "";
  for (let i = 0; i < total; i++) {
    s += i === active ? "\u25cf" : "\u25cb";
    if (i < total - 1) s += " ";
  }
  return center(s, width);
}

function toBeaufort(kmh) {
  const thresholds = [1, 6, 12, 20, 29, 39, 50, 62, 75, 89, 103, 118];
  for (let i = 0; i < thresholds.length; i++) {
    if (kmh < thresholds[i]) return String(i);
  }
  return "12";
}

const DIM = "\x1b[2m";
const BOLD = "\x1b[1m";
const BLUE = "\x1b[34m";
const ORANGE = "\x1b[33m";
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const RESET = "\x1b[0m";
const W = 42;
const IW = W - 4; // inner width

// ── Gather data ──────────────────────────────────────────────

let files;
try {
  files = fs.readdirSync(CACHE_DIR).filter((f) => f.endsWith(".json") && !f.includes("_raw"));
} catch {
  console.log("No cache directory found.");
  process.exit(0);
}

if (files.length === 0) {
  console.log("Cache is empty.");
  process.exit(0);
}

const byLocation = {};
for (const file of files) {
  const raw = fs.readFileSync(path.join(CACHE_DIR, file), "utf8");
  const entry = JSON.parse(raw);
  const name = path.basename(file, ".json");
  const [type, ...rest] = name.split("_");
  const loc = rest.join("_");
  if (!byLocation[loc]) byLocation[loc] = {};
  byLocation[loc][type] = { data: entry.data, ts: entry.ts };
}

for (const [loc, types] of Object.entries(byLocation)) {
  const locName = LOCATIONS[loc]?.name || loc;
  const weather = types.weather?.data || {};
  const tide = types.tide?.data || {};
  const watertemp = types.watertemp?.data || {};
  const latestTs = Math.max(
    types.weather?.ts || 0,
    types.tide?.ts || 0,
    types.watertemp?.ts || 0
  );

  console.log(`\n  ${BOLD}${locName.toUpperCase()}${RESET}\n`);

  // ── Water level (API + interpolated) ──
  const rising = tide.tideRising;
  const dir = rising != null ? (rising ? "Opk" : "Afg") : "---";
  const apiLvl = tide.waterLevel != null ? `${tide.waterLevel.toFixed(2)}m` : "--";
  let interpLvl = "--";
  if (tide.prevTideEpoch && tide.nextTideEpoch && tide.prevTideLevel != null && tide.nextTideLevel != null) {
    const now = Date.now() / 1000;
    const span = tide.nextTideEpoch - tide.prevTideEpoch;
    if (span > 0) {
      let t = (now - tide.prevTideEpoch) / span;
      t = Math.max(0, Math.min(1, t));
      const cosInterp = (1 - Math.cos(t * Math.PI)) / 2;
      const interp = tide.prevTideLevel + (tide.nextTideLevel - tide.prevTideLevel) * cosInterp;
      interpLvl = `${interp.toFixed(2)}m`;
    }
  }
  const lvl = interpLvl !== "--" ? interpLvl : apiLvl;
  const wt = watertemp.waterTemp != null ? `w${Math.round(watertemp.waterTemp)}\u00b0` : "";
  const at = weather.airTemp != null ? `${Math.round(weather.airTemp)}\u00b0` : "";
  const ws = weather.windSpeed != null ? `${Math.round(weather.windSpeed)}km/h` : "";

  const glanceLine1 = [dir, lvl, wt].filter(Boolean).join(" ");
  const glanceLine2 = [at, ws].filter(Boolean).join(" ");

  console.log(box("Glance", [
    center(`${BOLD}${glanceLine1}${RESET}`, IW),
    center(`${DIM}${glanceLine2}${RESET}`, IW),
  ], W));

  // ── Tide debug ──
  const prevInfo = tide.prevTideEpoch
    ? `${tide.prevTideType} ${tide.prevTideLevel?.toFixed(2)}m @ ${new Date(tide.prevTideEpoch * 1000).toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" })}`
    : `${DIM}none${RESET}`;
  const nextInfo = tide.nextTideEpoch
    ? `${tide.nextTideType} ${tide.nextTideLevel?.toFixed(2)}m @ ${new Date(tide.nextTideEpoch * 1000).toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" })}`
    : `${DIM}none${RESET}`;

  const tideDataLines = [
    `  API level:    ${BOLD}${apiLvl}${RESET}`,
    `  Interpolated: ${BOLD}${interpLvl}${RESET}`,
    `  Prev extremum: ${prevInfo}`,
    `  Next extremum: ${nextInfo}`,
  ];
  if (Array.isArray(tide.tideTable) && tide.tideTable.length > 0) {
    tideDataLines.push("");
    const nowSec = Date.now() / 1000;
    let lastDate = "";
    for (const e of tide.tideTable) {
      const dateStr = e.date || "";
      if (dateStr && dateStr !== lastDate) {
        tideDataLines.push(`  ${BOLD}${dateStr}${RESET}`);
        lastDate = dateStr;
      }
      const past = e.epoch < nowSec;
      const arrow = e.type === "HW" ? `${GREEN}\u25b2${RESET}` : `${RED}\u25bc${RESET}`;
      const c = past ? DIM : "";
      const r = past ? RESET : "";
      tideDataLines.push(`    ${c}${arrow} ${e.type} ${(e.level ?? 0).toFixed(2).padStart(6)}m  ${e.time}${r}`);
    }
  }
  console.log(box("Tide data", tideDataLines, W));

  // ── Page 1: Tide ──
  const arrowChar = rising != null ? (rising ? `${GREEN}\u25b2${RESET}` : `${RED}\u25bc${RESET}`) : " ";
  const tideLabel = rising != null ? (rising ? "Opkomend" : "Afgaand") : "---";
  const nextLine = tide.nextTideType
    ? `${tide.nextTideType} ${tide.nextTideLevel?.toFixed(2) || "--"}m  ${tide.nextTideTime || ""}`
    : `${DIM}geen getijdata${RESET}`;

  console.log(box("Page 1: Tide", [
    center(`${DIM}${locName.toUpperCase()}${RESET}`, IW),
    "",
    center(`${arrowChar}  ${BOLD}${lvl}${RESET}`, IW),
    center(`${DIM}${tideLabel}${RESET}`, IW),
    "",
    center(nextLine, IW),
    "",
    dots(0, 4, IW),
  ], W));

  // ── Page 2: Water ──
  const waterVal = watertemp.waterTemp != null
    ? `${BLUE}${BOLD}${watertemp.waterTemp.toFixed(1)}\u00b0C${RESET}`
    : `${DIM}--${RESET}`;

  console.log(box("Page 2: Water", [
    center(`${DIM}${locName.toUpperCase()}${RESET}`, IW),
    "",
    center(`${BLUE}\u2299${RESET}`, IW),
    center(waterVal, IW),
    center(`${DIM}Water${RESET}`, IW),
    "",
    center(`${BLUE}~~~~~${RESET}`, IW),
    "",
    dots(1, 4, IW),
  ], W));

  // ── Page 3: Weather ──
  const airVal = weather.airTemp != null
    ? `${ORANGE}\u2299${RESET}  ${BOLD}${weather.airTemp.toFixed(1)}\u00b0C${RESET}`
    : `${DIM}--${RESET}`;
  const bft = weather.windSpeed != null ? toBeaufort(weather.windSpeed) : "--";
  const windVal = weather.windSpeed != null
    ? `${BLUE}\u2261${RESET}  ${BOLD}${weather.windSpeed.toFixed(0)} km/h${RESET}`
    : `${DIM}--${RESET}`;

  console.log(box("Page 3: Weather", [
    center(`${DIM}${locName.toUpperCase()}${RESET}`, IW),
    "",
    center(airVal, IW),
    center(`${DIM}Air${RESET}`, IW),
    "",
    center(windVal, IW),
    center(`${DIM}Wind  Bft ${bft}${RESET}`, IW),
    "",
    dots(2, 4, IW),
  ], W));

  // ── Page 4: Sync ──
  const syncTime = latestTs > 0 ? fmtTime(latestTs) : "--:--";
  const syncDate = latestTs > 0 ? fmtDate(latestTs) : "---";
  const syncAge = latestTs > 0 ? `${DIM}(${fmtAge(Date.now() - latestTs)})${RESET}` : "";

  console.log(box("Page 4: Sync", [
    center(`${DIM}${locName.toUpperCase()}${RESET}`, IW),
    "",
    center(`${DIM}Laatste sync${RESET}`, IW),
    "",
    center(`${BOLD}${syncTime}${RESET}`, IW),
    center(`${DIM}${syncDate}${RESET}`, IW),
    center(syncAge, IW),
    "",
    dots(3, 4, IW),
  ], W));
}

console.log();
