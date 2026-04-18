// Standalone tide debug — reads raw RWS dump or fetches fresh data
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

dotenv.config();

const RWS_BASE = process.env.RWS_BASE_URL || "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES";
const CACHE_DIR = path.join(__dirname, "..", "cache");

interface RwsMeting {
  Tijdstip?: string;
  Meetwaarde?: { Waarde_Numeriek?: number };
}

interface RwsResponse {
  Succesvol?: boolean;
  WaarnemingenLijst?: { MetingenLijst?: RwsMeting[] }[];
}

interface TidePoint {
  time: string;
  value: number;
}

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

async function getRawData(loc: string): Promise<RwsResponse> {
  const dumpFile = path.join(CACHE_DIR, `tide_${loc}_raw.json`);
  try {
    const raw = fs.readFileSync(dumpFile, "utf8");
    console.log(`Reading cached raw data from ${dumpFile}\n`);
    return JSON.parse(raw);
  } catch {}

  console.log("No cached raw data, fetching from RWS...\n");
  const now = new Date();
  const start = new Date(now.getTime() - 1 * 3600 * 1000);
  const end = new Date(now.getTime() + 12 * 3600 * 1000);

  const res = await fetch(`${RWS_BASE}/OphalenWaarnemingen`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      Locatie: { Code: loc },
      AquoPlusWaarnemingMetadata: {
        AquoMetadata: { Grootheid: { Code: "WATHTE" }, ProcesType: "astronomisch" },
      },
      Periode: { Begindatumtijd: fmtDate(start), Einddatumtijd: fmtDate(end) },
    }),
  });
  const data = await res.json() as RwsResponse;
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  fs.writeFileSync(dumpFile, JSON.stringify(data, null, 2));
  return data;
}

async function main(): Promise<void> {
  const loc = process.argv[2] || "vlissingen";
  const data = await getRawData(loc);

  if (!data.Succesvol) {
    console.log("API error:", JSON.stringify(data, null, 2).slice(0, 500));
    return;
  }

  const metingen = data.WaarnemingenLijst?.[0]?.MetingenLijst;
  if (!metingen) { console.log("No MetingenLijst"); return; }

  const points: TidePoint[] = metingen
    .map((m) => ({ time: m.Tijdstip as string, value: m.Meetwaarde?.Waarde_Numeriek as number }))
    .filter((p) => p.time != null && p.value != null)
    .map((p) => ({ ...p, value: p.value / 100 }));

  console.log(`${points.length} data points:\n`);
  console.log("  RWS timestamp                          Level(m)  local");
  console.log("  " + "-".repeat(60));

  const nowMs = Date.now();
  let nowIdx = 0;
  let minDiff = Infinity;
  for (let i = 0; i < points.length; i++) {
    const diff = Math.abs(new Date(points[i].time).getTime() - nowMs);
    if (diff < minDiff) { minDiff = diff; nowIdx = i; }
  }

  for (let i = 0; i < points.length; i++) {
    const marker = i === nowIdx ? " <<NOW" : "";
    console.log(`  ${points[i].time}  ${points[i].value.toFixed(3).padStart(8)}  ${localTime(points[i].time)}${marker}`);
  }

  console.log();
  console.log(`nowIdx=${nowIdx} time=${points[nowIdx].time} local=${localTime(points[nowIdx].time)} level=${points[nowIdx].value.toFixed(3)}m`);
  console.log();

  // Direction-change algorithm with plateau midpoint (same as server)
  console.log("Direction-change extremum search:");
  let lastDirection: "up" | "down" | null = null;
  let extremeIndex = nowIdx;
  let extremeValue = points[nowIdx].value;
  let plateauStart = nowIdx;

  for (let i = nowIdx + 1; i < points.length; i++) {
    const curr = points[i].value;
    const prev = points[i - 1].value;

    if (curr > prev) {
      if (lastDirection === "down") {
        const midIdx = Math.floor((plateauStart + extremeIndex) / 2);
        console.log(`  FOUND LW: plateau i=${plateauStart}-${extremeIndex}, mid=${midIdx}`);
        console.log(`    time: ${points[midIdx].time}`);
        console.log(`    local time: ${localTime(points[midIdx].time)}`);
        console.log(`    level: ${extremeValue.toFixed(3)}m`);
        break;
      }
      lastDirection = "up";
      plateauStart = i;
      extremeIndex = i;
      extremeValue = curr;
    } else if (curr < prev) {
      if (lastDirection === "up") {
        const midIdx = Math.floor((plateauStart + extremeIndex) / 2);
        console.log(`  FOUND HW: plateau i=${plateauStart}-${extremeIndex}, mid=${midIdx}`);
        console.log(`    time: ${points[midIdx].time}`);
        console.log(`    local time: ${localTime(points[midIdx].time)}`);
        console.log(`    level: ${extremeValue.toFixed(3)}m`);
        break;
      }
      lastDirection = "down";
      plateauStart = i;
      extremeIndex = i;
      extremeValue = curr;
    } else {
      // Plateau: extend range
      extremeIndex = i;
    }
  }
}

main().catch(console.error);
