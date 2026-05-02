import http from "http";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

import {
  LOCATIONS,
  Location,
  LunarEvent,
  getMoonInfo,
  getLunarEvents,
} from "./lib";

dotenv.config();

const PORT = parseInt(process.env.PORT || "31415", 10);
const RWS_BASE =
  process.env.RWS_BASE_URL ||
  "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES";
const OPENMETEO_BASE =
  process.env.OPENMETEO_BASE_URL || "https://api.open-meteo.com/v1";
const CACHE_TTL = parseInt(process.env.CACHE_TTL_MS || "3600000", 10);

const CACHE_DIR = path.join(__dirname, "..", "cache");
const LOG_FILE = path.join(__dirname, "..", "logs", "server.log");

// ── Logging ──────────────────────────────────────────────────

fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });

function log(msg: string): void {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stdout.write(line);
  fs.appendFileSync(LOG_FILE, line);
}

// ── Cache ────────────────────────────────────────────────────

fs.mkdirSync(CACHE_DIR, { recursive: true });

interface CacheEntry<T> {
  ts: number;
  data: T;
}

function getCached<T>(key: string): T | null {
  const file = path.join(CACHE_DIR, `${key}.json`);
  try {
    const raw = fs.readFileSync(file, "utf8");
    const entry: CacheEntry<T> = JSON.parse(raw);
    const age = Math.floor((Date.now() - entry.ts) / 1000);
    if (Date.now() - entry.ts < CACHE_TTL) {
      log(`  cache READ  ${file} (age ${age}s) ${JSON.stringify(entry.data)}`);
      return entry.data;
    }
    log(`  cache STALE ${file} (age ${age}s > TTL ${CACHE_TTL / 1000}s)`);
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    log(`  cache MISS  ${file} (${e.code || e.message})`);
  }
  return null;
}

function setCache<T>(key: string, data: T): void {
  const file = path.join(CACHE_DIR, `${key}.json`);
  log(`  cache WRITE ${file} ${JSON.stringify(data)}`);
  fs.writeFileSync(file, JSON.stringify({ ts: Date.now(), data }));
}

// ── Types ────────────────────────────────────────────────────

interface WeatherResult {
  airTemp: number | null;
  windSpeed: number | null;
}

interface TideExtremum {
  type: "HW" | "LW" | "SPR" | "DTJ";
  level?: number;
  epoch: number;
}

interface TideResult {
  tideTable?: TideExtremum[];
}

interface WaterTempResult {
  waterTemp?: number;
}

interface TidePoint {
  time: string;
  value: number;
}

interface ParsedExtremum {
  type: "HW" | "LW";
  idx: number;
  level: number;
  epoch: number;
}

// ── Upstream fetchers ────────────────────────────────────────

async function fetchWeather(loc: Location): Promise<WeatherResult> {
  const key = `weather_${loc.rwsCode}`;
  const cached = getCached<WeatherResult>(key);
  if (cached) {
    log("  weather: cache hit");
    return cached;
  }

  const url = `${OPENMETEO_BASE}/forecast?latitude=${loc.lat}&longitude=${loc.lon}&current=temperature_2m,wind_speed_10m`;
  log(`  weather: GET ${url}`);
  const res = await fetch(url);
  const body = await res.json() as { current?: { temperature_2m?: number; wind_speed_10m?: number } };

  const result: WeatherResult = {
    airTemp: body.current?.temperature_2m ?? null,
    windSpeed: body.current?.wind_speed_10m ?? null,
  };
  setCache(key, result);
  return result;
}

type ProcesType = "astronomisch" | "verwachting";

async function fetchTideExtrema(loc: Location, procesType: ProcesType): Promise<ParsedExtremum[]> {
  const key = `tide_${procesType}_${loc.rwsCode}`;
  const cached = getCached<ParsedExtremum[]>(key);
  if (cached) {
    log(`  tide(${procesType}): cache hit`);
    return cached;
  }

  const now = new Date();
  const start = new Date(now.getTime() - 7 * 3600 * 1000);
  const end = new Date(now.getTime() + 7 * 24 * 3600 * 1000);

  const payload = {
    Locatie: { Code: loc.rwsCode },
    AquoPlusWaarnemingMetadata: {
      AquoMetadata: {
        Grootheid: { Code: "WATHTE" },
        ProcesType: procesType,
      },
    },
    Periode: {
      Begindatumtijd: fmtDate(start),
      Einddatumtijd: fmtDate(end),
    },
  };

  const url = `${RWS_BASE}/OphalenWaarnemingen`;
  log(`  tide(${procesType}): POST ${url}`);
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(payload),
  });
  const body = await res.json() as RwsResponse;

  // Dump raw response for debugging — astronomisch keeps the legacy filename
  // so debug-tide.ts can read it without an extra suffix.
  const suffix = procesType === "astronomisch" ? "" : `_${procesType}`;
  const dumpFile = path.join(CACHE_DIR, `tide_${loc.rwsCode}${suffix}_raw.json`);
  fs.writeFileSync(dumpFile, JSON.stringify(body, null, 2));

  const extrema = parseExtrema(body);
  log(`  tide(${procesType}): ${extrema.length} extrema`);
  setCache(key, extrema);
  return extrema;
}

async function fetchTide(loc: Location): Promise<TideResult> {
  // Fetch both series in parallel. Verwachting (weather-adjusted, refreshed
  // every 6h) takes precedence within its forecast window — typically ~2 days
  // — and astronomisch fills in beyond the last verwachting extremum.
  const [astroExtrema, verwExtrema] = await Promise.all([
    fetchTideExtrema(loc, "astronomisch").catch((err) => {
      log(`  tide(astronomisch): error ${(err as Error).message}`);
      return [] as ParsedExtremum[];
    }),
    fetchTideExtrema(loc, "verwachting").catch((err) => {
      log(`  tide(verwachting): error ${(err as Error).message}`);
      return [] as ParsedExtremum[];
    }),
  ]);

  let merged: ParsedExtremum[];
  if (verwExtrema.length > 0) {
    // The last verwachting extremum and the next astronomisch one often
    // describe the same physical HW/LW (predictions a few minutes apart).
    // Skip astro extrema until the type alternates — that's the genuine next
    // turn of the tide, and astronomisch alternates cleanly from there.
    const lastVerw = verwExtrema[verwExtrema.length - 1];
    const tailStart = astroExtrema.findIndex(
      (e) => e.epoch > lastVerw.epoch && e.type !== lastVerw.type,
    );
    const tail = tailStart >= 0 ? astroExtrema.slice(tailStart) : [];
    merged = [...verwExtrema, ...tail];
    log(`  tide: merged ${verwExtrema.length} verw + ${tail.length} astro tail`);
  } else {
    merged = astroExtrema;
    log(`  tide: astronomisch only (no verwachting data)`);
  }

  return buildTideTable(merged);
}

async function fetchWaterTemp(loc: Location): Promise<WaterTempResult> {
  const key = `watertemp_${loc.rwsCode}`;
  const cached = getCached<WaterTempResult>(key);
  if (cached) {
    log("  waterTemp: cache hit");
    return cached;
  }

  const payload = {
    LocatieLijst: [{ Code: loc.rwsCode }],
    AquoPlusWaarnemingMetadataLijst: [
      {
        AquoMetadata: {
          Grootheid: { Code: "T" },
          Compartiment: { Code: "OW" },
        },
      },
    ],
  };

  const url = `${RWS_BASE}/OphalenLaatsteWaarnemingen`;
  log(`  waterTemp: POST ${url}`);
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(payload),
  });
  const body = await res.json() as RwsResponse;

  const result = parseWaterTemp(body);
  setCache(key, result);
  return result;
}

// ── Parsers ──────────────────────────────────────────────────

interface RwsMeting {
  Tijdstip?: string;
  Meetwaarde?: { Waarde_Numeriek?: number };
}

interface RwsWaarneming {
  MetingenLijst?: RwsMeting[];
}

interface RwsResponse {
  WaarnemingenLijst?: RwsWaarneming[];
}

function parseExtrema(data: RwsResponse): ParsedExtremum[] {
  const lijst = data?.WaarnemingenLijst;
  if (!Array.isArray(lijst) || lijst.length === 0) return [];

  const metingen = lijst[0]?.MetingenLijst;
  if (!Array.isArray(metingen) || metingen.length < 3) return [];

  const points: TidePoint[] = metingen
    .map((m) => ({
      time: m.Tijdstip as string,
      value: m.Meetwaarde?.Waarde_Numeriek as number,
    }))
    .filter((p) => p.time != null && p.value != null)
    .map((p) => ({ ...p, value: p.value / 100 }));

  if (points.length < 3) return [];

  // Direction-change algorithm with plateau midpoints.
  return findExtrema(points);
}

function buildTideTable(extrema: ParsedExtremum[]): TideResult {
  const result: TideResult = {};
  if (extrema.length === 0) return result;

  // Tide table: most recent past extremum + next ~7 days of extrema.
  // RWS gives us 7 days forward; watch parses 28 HW/LW + a few SPR/DTJ fine.
  // The watch derives prev/next/direction from this table at render time, so
  // it stays accurate when an extremum passes between 30-min syncs.
  const nowSec = Date.now() / 1000;
  const futureLimit = 28; // ~7 days of HW/LW
  const past = extrema.filter((e) => e.epoch <= nowSec).slice(-1);
  const future = extrema.filter((e) => e.epoch > nowSec).slice(0, futureLimit);
  if (past.length > 0) {
    const p = past[0];
    log(`  tide: prev ${p.type} at ${localTime(new Date(p.epoch * 1000).toISOString())} = ${p.level.toFixed(3)}m`);
  }
  if (future.length > 0) {
    const n = future[0];
    log(`  tide: next ${n.type} at ${localTime(new Date(n.epoch * 1000).toISOString())} = ${n.level.toFixed(3)}m`);
  }
  // Only type/level/epoch — time and date are derived on the watch from epoch.
  // Keeps the parsed Dictionary small (every extra key costs ~40-80B in CIQ).
  const tideRows: TideExtremum[] = [...past, ...future].map((e) => ({
    type: e.type,
    level: Math.round(e.level * 100) / 100,
    epoch: Math.floor(e.epoch),
  }));

  // Inject springtij/doodtij markers within the same time range.
  if (tideRows.length > 0) {
    const rangeStart = tideRows[0].epoch * 1000;
    const rangeEnd = tideRows[tideRows.length - 1].epoch * 1000;
    const lunar: LunarEvent[] = getLunarEvents(rangeStart, rangeEnd);
    tideRows.push(...lunar);
    tideRows.sort((a, b) => a.epoch - b.epoch);
  }
  result.tideTable = tideRows;

  return result;
}

function findExtrema(points: TidePoint[]): ParsedExtremum[] {
  const extrema: ParsedExtremum[] = [];
  let dir: "up" | "down" | null = null;
  let extIdx = 0;
  let extVal = points[0].value;
  let platStart = 0;

  for (let i = 1; i < points.length; i++) {
    const curr = points[i].value;
    const prev = points[i - 1].value;

    if (curr > prev) {
      if (dir === "down") {
        const midIdx = Math.floor((platStart + extIdx) / 2);
        extrema.push({
          type: "LW", idx: midIdx, level: extVal,
          epoch: new Date(points[midIdx].time).getTime() / 1000,
        });
      }
      dir = "up";
      platStart = i;
      extIdx = i;
      extVal = curr;
    } else if (curr < prev) {
      if (dir === "up") {
        const midIdx = Math.floor((platStart + extIdx) / 2);
        extrema.push({
          type: "HW", idx: midIdx, level: extVal,
          epoch: new Date(points[midIdx].time).getTime() / 1000,
        });
      }
      dir = "down";
      platStart = i;
      extIdx = i;
      extVal = curr;
    } else {
      extIdx = i;
    }
  }

  return extrema;
}

function parseWaterTemp(data: RwsResponse): WaterTempResult {
  const lijst = data?.WaarnemingenLijst;
  if (!Array.isArray(lijst) || lijst.length === 0) return {};

  const metingen = lijst[0]?.MetingenLijst;
  if (!Array.isArray(metingen) || metingen.length === 0) return {};

  const val = metingen[metingen.length - 1]?.Meetwaarde?.Waarde_Numeriek;
  if (val == null) return {};

  return { waterTemp: Math.round(val * 10) / 10 };
}

// ── Helpers ──────────────────────────────────────────────────

function fmtDate(d: Date): string {
  return d.toISOString().replace("Z", "+00:00");
}

function localTime(ts: string): string {
  try {
    const d = new Date(ts);
    return d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit", hour12: false });
  } catch {
    return "??:??";
  }
}

// ── HTTP server ──────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://localhost:${PORT}`);
  const match = url.pathname.match(/^\/conditions\/(\w+)$/);

  if (!match) {
    log(`404 ${req.method} ${req.url}`);
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Use GET /conditions/{locationCode}" }));
    return;
  }

  const code = match[1];
  const loc = LOCATIONS[code];
  if (!loc) {
    log(`404 unknown location: ${code}`);
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: `Unknown location: ${code}` }));
    return;
  }

  log(`GET /conditions/${code}`);

  try {
    const hasTide = loc.tide !== false;
    const hasWaterTemp = loc.waterTemp !== false;
    const [weather, tide, waterTemp] = await Promise.all([
      fetchWeather(loc),
      hasTide ? fetchTide(loc) : Promise.resolve({}),
      hasWaterTemp ? fetchWaterTemp(loc) : Promise.resolve({}),
    ]);

    const result = {
      locName: loc.name,
      ...weather,
      ...tide,
      ...waterTemp,
      ...(hasTide ? getMoonInfo() : {}),
    };

    const json = JSON.stringify(result);
    log(`  -> ${json}`);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(json);
  } catch (err) {
    const e = err as Error;
    log(`  ERROR: ${e.message}`);
    res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: e.message }));
  }
});

server.listen(PORT, () => {
  log(`Swimfo server listening on http://localhost:${PORT}`);
});
