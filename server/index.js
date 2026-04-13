const http = require("http");
const fs = require("fs");
const path = require("path");

require("dotenv").config();

const PORT = parseInt(process.env.PORT || "31415", 10);
const RWS_BASE =
  process.env.RWS_BASE_URL ||
  "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES";
const OPENMETEO_BASE =
  process.env.OPENMETEO_BASE_URL || "https://api.open-meteo.com/v1";
const CACHE_TTL = parseInt(process.env.CACHE_TTL_MS || "3600000", 10);

const CACHE_DIR = path.join(__dirname, "cache");
const LOG_FILE = path.join(__dirname, "logs", "server.log");

// ── Locations ────────────────────────────────────────────────

const LOCATIONS = {
  vlissingen: {
    name: "Vlissingen",
    lat: 51.4425,
    lon: 3.5964,
    rwsCode: "vlissingen",
  },
  yerseke: {
    name: "Kattendijke",
    lat: 51.4933,
    lon: 3.96,
    rwsCode: "yerseke",
  },
};

// ── Logging ──────────────────────────────────────────────────

fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stdout.write(line);
  fs.appendFileSync(LOG_FILE, line);
}

// ── Cache ────────────────────────────────────────────────────

fs.mkdirSync(CACHE_DIR, { recursive: true });

function getCached(key) {
  const file = path.join(CACHE_DIR, `${key}.json`);
  try {
    const raw = fs.readFileSync(file, "utf8");
    const entry = JSON.parse(raw);
    const age = Math.floor((Date.now() - entry.ts) / 1000);
    if (Date.now() - entry.ts < CACHE_TTL) {
      log(`  cache READ  ${file} (age ${age}s) ${JSON.stringify(entry.data)}`);
      return entry.data;
    }
    log(`  cache STALE ${file} (age ${age}s > TTL ${CACHE_TTL / 1000}s)`);
  } catch (err) {
    log(`  cache MISS  ${file} (${err.code || err.message})`);
  }
  return null;
}

function setCache(key, data) {
  const file = path.join(CACHE_DIR, `${key}.json`);
  log(`  cache WRITE ${file} ${JSON.stringify(data)}`);
  fs.writeFileSync(file, JSON.stringify({ ts: Date.now(), data }));
}

// ── Upstream fetchers ────────────────────────────────────────

async function fetchWeather(loc) {
  const key = `weather_${loc.rwsCode}`;
  const cached = getCached(key);
  if (cached) {
    log("  weather: cache hit");
    return cached;
  }

  const url = `${OPENMETEO_BASE}/forecast?latitude=${loc.lat}&longitude=${loc.lon}&current=temperature_2m,wind_speed_10m`;
  log(`  weather: GET ${url}`);
  const res = await fetch(url);
  const body = await res.json();

  const result = {
    airTemp: body.current?.temperature_2m ?? null,
    windSpeed: body.current?.wind_speed_10m ?? null,
  };
  setCache(key, result);
  return result;
}

async function fetchTide(loc) {
  const key = `tide_${loc.rwsCode}`;
  const cached = getCached(key);
  if (cached) {
    log("  tide: cache hit");
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
        ProcesType: "astronomisch",
      },
    },
    Periode: {
      Begindatumtijd: fmtDate(start),
      Einddatumtijd: fmtDate(end),
    },
  };

  const url = `${RWS_BASE}/OphalenWaarnemingen`;
  log(`  tide: POST ${url}`);
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(payload),
  });
  const body = await res.json();

  // Dump raw response for debugging
  const dumpFile = path.join(CACHE_DIR, `tide_${loc.rwsCode}_raw.json`);
  fs.writeFileSync(dumpFile, JSON.stringify(body, null, 2));

  const result = parseTide(body);
  setCache(key, result);
  return result;
}

async function fetchWaterTemp(loc) {
  const key = `watertemp_${loc.rwsCode}`;
  const cached = getCached(key);
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
  const body = await res.json();

  const result = parseWaterTemp(body);
  setCache(key, result);
  return result;
}

// ── Parsers ──────────────────────────────────────────────────

function parseTide(data) {
  const result = {};
  const lijst = data?.WaarnemingenLijst;
  if (!Array.isArray(lijst) || lijst.length === 0) return result;

  const metingen = lijst[0]?.MetingenLijst;
  if (!Array.isArray(metingen) || metingen.length < 3) return result;

  const points = metingen
    .map((m) => ({
      time: m.Tijdstip,
      value: m.Meetwaarde?.Waarde_Numeriek,
    }))
    .filter((p) => p.time != null && p.value != null)
    .map((p) => ({ ...p, value: p.value / 100 }));

  if (points.length < 3) return result;

  // Closest to now
  const nowMs = Date.now();
  let nowIdx = 0;
  let minDiff = Infinity;
  for (let i = 0; i < points.length; i++) {
    const diff = Math.abs(new Date(points[i].time).getTime() - nowMs);
    if (diff < minDiff) {
      minDiff = diff;
      nowIdx = i;
    }
  }

  result.waterLevel = Math.round(points[nowIdx].value * 100) / 100;

  log(`  tide: ${points.length} points, nowIdx=${nowIdx} (${points[nowIdx].time})`);

  // Find all extrema using direction-change algorithm with plateau midpoints
  const extrema = findExtrema(points);
  log(`  tide: found ${extrema.length} extrema`);

  // Find previous and next extrema relative to now
  let prev = null;
  let next = null;
  for (let i = 0; i < extrema.length; i++) {
    if (extrema[i].epoch <= nowMs / 1000) {
      prev = extrema[i];
    } else if (!next) {
      next = extrema[i];
    }
  }

  if (prev) {
    log(`  tide: prev ${prev.type} at ${localTime(points[prev.idx].time)} = ${prev.level.toFixed(3)}m`);
    result.prevTideLevel = Math.round(prev.level * 100) / 100;
    result.prevTideEpoch = Math.floor(prev.epoch);
    result.prevTideType = prev.type;
  }

  if (next) {
    log(`  tide: next ${next.type} at ${localTime(points[next.idx].time)} = ${next.level.toFixed(3)}m`);
    result.nextTideLevel = Math.round(next.level * 100) / 100;
    result.nextTideEpoch = Math.floor(next.epoch);
    result.nextTideTime = localTime(points[next.idx].time);
    result.nextTideType = next.type;
  }

  if (prev && next) {
    result.tideRising = next.type === "HW";
  } else if (nowIdx > 0) {
    result.tideRising = points[nowIdx].value > points[nowIdx - 1].value;
  }

  // Tide table: all extrema with formatted times and dates
  result.tideTable = extrema.map((e) => ({
    type: e.type,
    level: Math.round(e.level * 100) / 100,
    epoch: Math.floor(e.epoch),
    time: localTime(points[e.idx].time),
    date: localDate(points[e.idx].time),
  }));

  return result;
}

function findExtrema(points) {
  const extrema = [];
  let dir = null;
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

function parseWaterTemp(data) {
  const lijst = data?.WaarnemingenLijst;
  if (!Array.isArray(lijst) || lijst.length === 0) return {};

  const metingen = lijst[0]?.MetingenLijst;
  if (!Array.isArray(metingen) || metingen.length === 0) return {};

  const val = metingen[metingen.length - 1]?.Meetwaarde?.Waarde_Numeriek;
  if (val == null) return {};

  return { waterTemp: Math.round(val * 10) / 10 };
}

// ── Helpers ──────────────────────────────────────────────────

function fmtDate(d) {
  return d.toISOString().replace("Z", "+00:00");
}

function localTime(ts) {
  try {
    const d = new Date(ts);
    return d.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit", hour12: false });
  } catch {
    return "??:??";
  }
}

function localDate(ts) {
  try {
    const d = new Date(ts);
    return d.toLocaleDateString("nl-NL", { weekday: "short", day: "numeric", month: "long" });
  } catch {
    return "???";
  }
}

// ── Moon phase ──────────────────────────────────────────────

function getMoonInfo() {
  // Reference new moon: Jan 6, 2000 18:14 UTC
  const refNewMoon = new Date("2000-01-06T18:14:00Z").getTime();
  const synodicMonth = 29.530588853; // days
  const now = Date.now();

  const daysSinceRef = (now - refNewMoon) / (24 * 3600 * 1000);
  const moonAge = ((daysSinceRef % synodicMonth) + synodicMonth) % synodicMonth;

  // Key phases (in days from new moon)
  const fullMoonAge = synodicMonth / 2; // ~14.77
  const firstQuarter = synodicMonth / 4; // ~7.38
  const lastQuarter = synodicMonth * 3 / 4; // ~22.15

  // Springtij peaks ~2 days after new/full moon.
  // Find distance to nearest new or full moon.
  const fromNewMoon = moonAge;
  const toNewMoon = synodicMonth - moonAge;
  const nearNew = Math.min(fromNewMoon, toNewMoon);
  const nearFull = Math.abs(moonAge - fullMoonAge);
  const nearSpring = Math.min(nearNew, nearFull); // days to/from nearest spring tide

  // Doodtij peaks ~2 days after first/last quarter.
  const nearQ1 = Math.abs(moonAge - firstQuarter);
  const nearQ3 = Math.abs(moonAge - lastQuarter);

  let label;
  if (nearSpring < 2.5) {
    label = "springtij";
  } else if (nearQ1 < 2.5 || nearQ3 < 2.5) {
    label = "doodtij";
  } else if (nearSpring <= 7) {
    label = `${Math.round(nearSpring)}d tot springtij`;
  } else {
    label = null; // not interesting enough to show
  }

  return { moonLabel: label };
}

// ── HTTP server ──────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
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
    const [weather, tide, waterTemp] = await Promise.all([
      fetchWeather(loc),
      fetchTide(loc),
      fetchWaterTemp(loc),
    ]);

    const result = {
      locName: loc.name,
      ...weather,
      ...tide,
      ...waterTemp,
      ...getMoonInfo(),
    };

    const json = JSON.stringify(result);
    log(`  -> ${json}`);
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(json);
  } catch (err) {
    log(`  ERROR: ${err.message}`);
    res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: err.message }));
  }
});

server.listen(PORT, () => {
  log(`Swimfo server listening on http://localhost:${PORT}`);
});
