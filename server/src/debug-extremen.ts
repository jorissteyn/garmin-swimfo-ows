// Standalone tide extremen debug — reads raw RWS dump from the
// "Groepering" query (GETETBRKD2). Fetches fresh if no cached dump.
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

dotenv.config();

const RWS_BASE = process.env.RWS_BASE_URL || "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES";
const CACHE_DIR = path.join(__dirname, "..", "cache");
const DEFAULT_GROEPERING = "GETETBRKD2";

interface RwsMeting {
  Tijdstip?: string;
  Meetwaarde?: { Waarde_Numeriek?: number };
}

interface RwsAquoMeta {
  Grootheid?: { Code?: string; Omschrijving?: string };
  Hoedanigheid?: { Code?: string; Omschrijving?: string };
  Groepering?: { Code?: string; Omschrijving?: string };
  ProcesType?: string;
}

interface RwsWaarneming {
  AquoMetadata?: RwsAquoMeta;
  MetingenLijst?: RwsMeting[];
}

interface RwsResponse {
  Succesvol?: boolean;
  Foutmelding?: string;
  WaarnemingenLijst?: RwsWaarneming[];
}

function fmtDate(d: Date): string {
  return d.toISOString().replace("Z", "+00:00");
}

function localTime(ts: string): string {
  try {
    const d = new Date(ts);
    return d.toLocaleString("nl-NL", {
      day: "2-digit", month: "2-digit",
      hour: "2-digit", minute: "2-digit",
      hour12: false, timeZone: "Europe/Amsterdam",
    });
  } catch {
    return "??";
  }
}

async function getRawData(loc: string, groepering: string): Promise<RwsResponse> {
  const dumpFile = path.join(CACHE_DIR, `tide_${loc}_raw.json`);
  try {
    const raw = fs.readFileSync(dumpFile, "utf8");
    console.log(`Reading cached raw data from ${dumpFile}\n`);
    return JSON.parse(raw);
  } catch {}

  console.log(`No cached raw data, fetching from RWS (Groepering=${groepering})...\n`);
  const now = new Date();
  const start = new Date(now.getTime() - 7 * 3600 * 1000);
  const end = new Date(now.getTime() + 7 * 24 * 3600 * 1000);

  const res = await fetch(`${RWS_BASE}/OphalenWaarnemingen`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      Locatie: { Code: loc },
      AquoPlusWaarnemingMetadata: {
        AquoMetadata: {
          Grootheid: { Code: "WATHTE" },
          Groepering: { Code: groepering },
        },
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
  const groepering = process.argv[3] || DEFAULT_GROEPERING;
  const data = await getRawData(loc, groepering);

  if (!data.Succesvol) {
    console.log("API error:", data.Foutmelding ?? JSON.stringify(data, null, 2).slice(0, 500));
    return;
  }

  const lijst = data.WaarnemingenLijst;
  if (!Array.isArray(lijst) || lijst.length === 0) {
    console.log("No WaarnemingenLijst entries — Groepering filter may be wrong.");
    return;
  }

  console.log(`Location:    ${loc}`);
  console.log(`Groepering:  ${groepering}`);
  console.log(`WaarnemingenLijst entries: ${lijst.length}\n`);

  // Per-list metadata header
  for (let i = 0; i < lijst.length; i++) {
    const meta = lijst[i].AquoMetadata;
    console.log(`── WaarnemingenLijst[${i}] ${"─".repeat(50)}`);
    console.log(`  Grootheid:     ${meta?.Grootheid?.Code ?? "?"}  (${meta?.Grootheid?.Omschrijving ?? ""})`);
    console.log(`  Hoedanigheid:  ${meta?.Hoedanigheid?.Code ?? "?"}  (${meta?.Hoedanigheid?.Omschrijving ?? ""})`);
    console.log(`  Groepering:    ${meta?.Groepering?.Code ?? "?"}  (${meta?.Groepering?.Omschrijving ?? ""})`);
    console.log(`  ProcesType:    ${meta?.ProcesType ?? "?"}`);
    console.log(`  MetingenLijst: ${lijst[i].MetingenLijst?.length ?? 0} entries`);
  }
  console.log();

  // Flatten + classify by neighbor comparison (extrema strictly alternate
  // HW↔LW, so the higher of any adjacent pair is HW).
  const pts: { epoch: number; level: number }[] = [];
  for (const w of lijst) {
    const metingen = w.MetingenLijst ?? [];
    for (const m of metingen) {
      if (m.Tijdstip == null || m.Meetwaarde?.Waarde_Numeriek == null) continue;
      pts.push({
        epoch: new Date(m.Tijdstip).getTime() / 1000,
        level: m.Meetwaarde.Waarde_Numeriek / 100,
      });
    }
  }
  pts.sort((a, b) => a.epoch - b.epoch);

  const nowSec = Date.now() / 1000;
  console.log(`Classified extrema (chronological, ${pts.length} entries):`);
  console.log("  When                          Type   Level   Past/Next");
  console.log("  " + "-".repeat(60));
  for (let i = 0; i < pts.length; i++) {
    const neighbor = i + 1 < pts.length ? pts[i + 1] : pts[i - 1];
    const type = neighbor && pts[i].level >= neighbor.level ? "HW" : "LW";
    const when = localTime(new Date(pts[i].epoch * 1000).toISOString());
    const marker = pts[i].epoch <= nowSec ? "past" : "next";
    console.log(`  ${when.padEnd(28)}  ${type}    ${pts[i].level.toFixed(2).padStart(6)}m   ${marker}`);
  }

  // First meting in full so any future RWS schema additions are easy to spot.
  const firstM = lijst[0]?.MetingenLijst?.[0];
  if (firstM) {
    console.log("\nFirst meting (full structure):");
    console.log(JSON.stringify(firstM, null, 2));
  }
}

main().catch(console.error);
