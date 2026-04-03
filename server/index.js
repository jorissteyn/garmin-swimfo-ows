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
    if (Date.now() - entry.ts < CACHE_TTL) {
      return entry.data;
    }
  } catch {}
  return null;
}

function setCache(key, data) {
  const file = path.join(CACHE_DIR, `${key}.json`);
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
  const start = new Date(now.getTime() - 1 * 3600 * 1000);
  const end = new Date(now.getTime() + 12 * 3600 * 1000);

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

  if (nowIdx > 0) {
    result.tideRising = points[nowIdx].value > points[nowIdx - 1].value;
  }

  log(`  tide: ${points.length} points, nowIdx=${nowIdx} (${points[nowIdx].time})`);

  // Direction-change algorithm: track when tide direction reverses to find
  // true extrema. For plateaus (multiple points at the same extreme value),
  // use the midpoint of the plateau as the reported time.
  let lastDirection = null; // "up" or "down"
  let extremeIndex = nowIdx;
  let extremeValue = points[nowIdx].value;
  let plateauStart = nowIdx; // first index at the current extreme value

  for (let i = nowIdx + 1; i < points.length; i++) {
    const curr = points[i].value;
    const prev = points[i - 1].value;

    if (curr > prev) {
      if (lastDirection === "down") {
        // Direction changed down→up: we passed a low tide
        // Use midpoint of plateau for the reported time
        const midIdx = Math.floor((plateauStart + extremeIndex) / 2);
        log(`  tide: LW at ${points[midIdx].time} = ${extremeValue.toFixed(3)}m (plateau ${plateauStart}-${extremeIndex})`);
        result.nextTideLevel = Math.round(extremeValue * 100) / 100;
        result.nextTideTime = localTime(points[midIdx].time);
        result.nextTideType = "LW";
        break;
      }
      lastDirection = "up";
      plateauStart = i;
      extremeIndex = i;
      extremeValue = curr;
    } else if (curr < prev) {
      if (lastDirection === "up") {
        // Direction changed up→down: we passed a high tide
        const midIdx = Math.floor((plateauStart + extremeIndex) / 2);
        log(`  tide: HW at ${points[midIdx].time} = ${extremeValue.toFixed(3)}m (plateau ${plateauStart}-${extremeIndex})`);
        result.nextTideLevel = Math.round(extremeValue * 100) / 100;
        result.nextTideTime = localTime(points[midIdx].time);
        result.nextTideType = "HW";
        break;
      }
      lastDirection = "down";
      plateauStart = i;
      extremeIndex = i;
      extremeValue = curr;
    } else {
      // curr == prev: plateau, extend the range
      extremeIndex = i;
    }
  }

  return result;
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
