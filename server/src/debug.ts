import fs from "fs";
import path from "path";
import { LOCATIONS, getMoonInfo } from "./lib";

const CACHE_DIR = path.join(__dirname, "..", "cache");

interface TideExtremum {
  type: "HW" | "LW" | "SPR" | "DTJ";
  level?: number;
  epoch: number;
}

interface TideData {
  tideTable?: TideExtremum[];
}

interface WeatherData {
  airTemp?: number;
  windSpeed?: number;
}

interface WaterTempData {
  waterTemp?: number;
}

interface CacheTyped<T> {
  data: T;
  ts: number;
}

type AnyCache = CacheTyped<TideData> | CacheTyped<WeatherData> | CacheTyped<WaterTempData>;

function fmtAge(ms: number): string {
  const sec = Math.floor(ms / 1000);
  if (sec < 60) return `${sec}s ago`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}m ago`;
  return `${Math.floor(min / 60)}h ${min % 60}m ago`;
}

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function fmtTime(ts: number): string {
  const d = new Date(ts);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fmtDate(ts: number): string {
  const d = new Date(ts);
  const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

function box(title: string, lines: string[], width: number): string {
  const bar = "\u2500".repeat(width - 2);
  const out: string[] = [];
  out.push(`\u250c\u2500 ${title} ${bar.slice(title.length + 3)}\u2510`);
  for (const line of lines) {
    const padding = width - 2 - stripAnsi(line).length;
    out.push(`\u2502 ${line}${" ".repeat(Math.max(0, padding))}\u2502`);
  }
  out.push(`\u2514${bar}\u2518`);
  return out.join("\n");
}

function stripAnsi(s: string): string {
  return s.replace(/\x1b\[[0-9;]*m/g, "");
}

function center(text: string, width: number): string {
  const len = stripAnsi(text).length;
  const pad = Math.max(0, Math.floor((width - len) / 2));
  return " ".repeat(pad) + text;
}

function dots(active: number, total: number, width: number): string {
  let s = "";
  for (let i = 0; i < total; i++) {
    s += i === active ? "\u25cf" : "\u25cb";
    if (i < total - 1) s += " ";
  }
  return center(s, width);
}

function toBeaufort(kmh: number): string {
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

let files: string[];
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

interface LocCacheBucket {
  weather?: CacheTyped<WeatherData>;
  tide?: CacheTyped<TideData>;
  watertemp?: CacheTyped<WaterTempData>;
}

const byLocation: Record<string, LocCacheBucket> = {};
for (const file of files) {
  const raw = fs.readFileSync(path.join(CACHE_DIR, file), "utf8");
  const entry = JSON.parse(raw);
  const name = path.basename(file, ".json");
  const [type, ...rest] = name.split("_");
  const loc = rest.join("_");
  if (!byLocation[loc]) byLocation[loc] = {};
  (byLocation[loc] as Record<string, AnyCache>)[type] = { data: entry.data, ts: entry.ts };
}

for (const [loc, types] of Object.entries(byLocation)) {
  const locName = LOCATIONS[loc]?.name || loc;
  const weather: WeatherData = types.weather?.data || {};
  const tide: TideData = types.tide?.data || {};
  const watertemp: WaterTempData = types.watertemp?.data || {};
  const latestTs = Math.max(
    types.weather?.ts || 0,
    types.tide?.ts || 0,
    types.watertemp?.ts || 0
  );

  console.log(`\n  ${BOLD}${locName.toUpperCase()}${RESET}\n`);

  // Pick prev/next extrema from tideTable at current time, mirroring the watch.
  const nowSec = Date.now() / 1000;
  let prevX: TideExtremum | null = null;
  let nextX: TideExtremum | null = null;
  if (Array.isArray(tide.tideTable)) {
    for (const e of tide.tideTable) {
      if (e.type !== "HW" && e.type !== "LW") continue;
      if (e.epoch <= nowSec) prevX = e;
      else if (!nextX) { nextX = e; break; }
    }
  }
  const rising = prevX && nextX ? (nextX.level ?? 0) > (prevX.level ?? 0) : null;
  const dir = rising != null ? (rising ? "Opk" : "Afg") : "---";
  let lvl = "--";
  if (prevX && nextX) {
    const span = nextX.epoch - prevX.epoch;
    if (span > 0) {
      let t = (nowSec - prevX.epoch) / span;
      t = Math.max(0, Math.min(1, t));
      const cosInterp = (1 - Math.cos(t * Math.PI)) / 2;
      const interp = (prevX.level ?? 0) + ((nextX.level ?? 0) - (prevX.level ?? 0)) * cosInterp;
      lvl = `${interp.toFixed(2)}m`;
    }
  }
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
  const fmtExtremum = (x: TideExtremum): string =>
    `${x.type} ${(x.level ?? 0).toFixed(2)}m @ ${new Date(x.epoch * 1000).toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Amsterdam" })}`;
  const prevInfo = prevX ? fmtExtremum(prevX) : `${DIM}none${RESET}`;
  const nextInfo = nextX ? fmtExtremum(nextX) : `${DIM}none${RESET}`;

  const tideDataLines = [
    `  Interpolated:  ${BOLD}${lvl}${RESET}`,
    `  Prev extremum: ${prevInfo}`,
    `  Next extremum: ${nextInfo}`,
  ];
  if (Array.isArray(tide.tideTable) && tide.tideTable.length > 0) {
    tideDataLines.push("");
    const dateKey = (epoch: number): string =>
      new Date(epoch * 1000).toLocaleDateString("nl-NL", {
        weekday: "short", day: "numeric", month: "short",
        timeZone: "Europe/Amsterdam",
      });

    // Pass 1: index lunar labels by date.
    const lunarByDate: Record<string, string> = {};
    for (const e of tide.tideTable) {
      if (e.type !== "SPR" && e.type !== "DTJ") continue;
      lunarByDate[dateKey(e.epoch)] = e.type === "SPR" ? "springtij" : "doodtij";
    }

    // Pass 2: emit header (+ optional sub) per date, then HW/LW rows only.
    let lastDate = "";
    for (const e of tide.tideTable) {
      const dateStr = dateKey(e.epoch);
      if (dateStr !== lastDate) {
        tideDataLines.push(`  ${BOLD}${dateStr}${RESET}`);
        const sub = lunarByDate[dateStr];
        if (sub) tideDataLines.push(`    ${DIM}${sub}${RESET}`);
        lastDate = dateStr;
      }
      if (e.type === "SPR" || e.type === "DTJ") continue;
      const past = e.epoch < nowSec;
      const c = past ? DIM : "";
      const r = past ? RESET : "";
      const time = new Date(e.epoch * 1000).toLocaleTimeString("nl-NL", {
        hour: "2-digit", minute: "2-digit", hour12: false,
        timeZone: "Europe/Amsterdam",
      });
      const arrowColor = past ? DIM : (e.type === "HW" ? GREEN : RED);
      const arrow = e.type === "HW" ? `${arrowColor}\u25b2${RESET}` : `${arrowColor}\u25bc${RESET}`;
      const label = `${arrowColor}${e.type}${RESET}`;
      tideDataLines.push(`    ${c}${arrow} ${label} ${(e.level ?? 0).toFixed(2).padStart(6)}m  ${time}${r}`);
    }
  }
  console.log(box("Tide data", tideDataLines, W));

  // ── Spring/neap tide (computed live) ──
  const moon = getMoonInfo();
  const moonLine = moon.moonLabel || "";

  // ── Page 1: Tide ──
  const arrowChar = rising != null ? (rising ? `${GREEN}\u25b2${RESET}` : `${RED}\u25bc${RESET}`) : " ";
  const tideLabel = rising != null ? (rising ? "Opkomend" : "Afgaand") : "---";
  const nextTimeStr = nextX
    ? new Date(nextX.epoch * 1000).toLocaleTimeString("nl-NL", {
        hour: "2-digit", minute: "2-digit", hour12: false,
        timeZone: "Europe/Amsterdam",
      })
    : "";
  const nextLine = nextX
    ? `${nextX.type} ${(nextX.level ?? 0).toFixed(2)}m  ${nextTimeStr}`
    : `${DIM}geen getijdata${RESET}`;

  const tidePage = [
    center(`${DIM}${locName.toUpperCase()}${RESET}`, IW),
    "",
    center(`${arrowChar}  ${BOLD}${lvl}${RESET}`, IW),
    center(`${DIM}${tideLabel}${RESET}`, IW),
    "",
    center(nextLine, IW),
  ];
  if (moonLine) {
    tidePage.push(center(`${DIM}${moonLine}${RESET}`, IW));
  }
  tidePage.push("");
  tidePage.push(dots(0, 4, IW));
  console.log(box("Page 1: Tide", tidePage, W));

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
