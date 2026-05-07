// Print every location the watch app knows about, parsed from the canonical
// watch-side sources: source/Locations.mc (id → name/lat/lon/locationSlug) and
// resources/strings/strings.xml (resource id → display label). Pairs nicely
// with list-remote-locations.ts (which lists every RWS station that *has*
// tide data) — diff the two to see candidates we could still add.
//
// Usage: `npm run list-supported-locations` (or
// `make server-list-supported-locations`).

import fs from "fs";
import path from "path";

const REPO_ROOT = path.join(__dirname, "..", "..");
const LOC_MC = path.join(REPO_ROOT, "source", "Locations.mc");
const STRINGS_XML = path.join(REPO_ROOT, "resources", "strings", "strings.xml");

interface LocBlock {
  name: string;
  lat: number;
  lon: number;
  locationSlug: string;
  rwsCode: string;
}

interface SupportedLoc extends LocBlock {
  id: number;
  labelRes: string;
  label: string;
}

function readSource(file: string): string {
  return fs.readFileSync(file, "utf8");
}

// Parse one `{ "name" => "X", "lat" => 1.23, ... }` literal body (the part
// inside the braces). Numeric values are parsed as floats; everything else
// is returned as the raw string contents of its quotes.
function parseDictBody(body: string): LocBlock {
  const out: Record<string, string | number> = {};
  const re = /"(\w+)"\s*=>\s*(?:"([^"]*)"|(-?\d+(?:\.\d+)?))/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(body))) {
    out[m[1]] = m[2] !== undefined ? m[2] : parseFloat(m[3]);
  }
  return {
    name: String(out.name ?? ""),
    lat: Number(out.lat ?? 0),
    lon: Number(out.lon ?? 0),
    locationSlug: String(out.locationSlug ?? ""),
    rwsCode: String(out.rwsCode ?? ""),
  };
}

// Pull `function get(...) { ... }` body so we can scope our id-block search.
// Brace-counting because Monkey C dict literals also use braces.
function extractFnBody(src: string, fnName: string): string {
  const startMatch = new RegExp(`function\\s+${fnName}\\s*\\([^)]*\\)[^{]*\\{`).exec(src);
  if (!startMatch) throw new Error(`Could not find function ${fnName}`);
  let depth = 1;
  let i = startMatch.index + startMatch[0].length;
  for (; i < src.length && depth > 0; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}") depth--;
  }
  return src.slice(startMatch.index + startMatch[0].length, i - 1);
}

function parseLocations(): SupportedLoc[] {
  const src = readSource(LOC_MC);

  const countMatch = /function\s+count\s*\([^)]*\)[^{]*\{\s*return\s+(\d+)/.exec(src);
  if (!countMatch) throw new Error("count() not found in Locations.mc");
  const count = parseInt(countMatch[1], 10);

  // Parse get(): explicit `if (id == N)` branches plus a trailing default
  // return (id 0). Each branch's body is a dict literal we feed to
  // parseDictBody.
  const getBody = extractFnBody(src, "get");
  const blocks = new Map<number, LocBlock>();
  const branchRe = /if\s*\(\s*id\s*==\s*(\d+)\s*\)\s*\{\s*return\s*\{([^}]+)\}\s*;/g;
  let m: RegExpExecArray | null;
  while ((m = branchRe.exec(getBody))) {
    blocks.set(parseInt(m[1], 10), parseDictBody(m[2]));
  }
  // Default: the last `return { ... };` in the function body that isn't
  // attached to an `if`. Strip out the matched branches first to find it.
  const tail = getBody.replace(branchRe, "");
  const defaultMatch = /return\s*\{([^}]+)\}\s*;/.exec(tail);
  if (defaultMatch) blocks.set(0, parseDictBody(defaultMatch[1]));

  // Parse settingsLabelRes(): id → resource id (e.g. "locKats").
  const labelBody = extractFnBody(src, "settingsLabelRes");
  const labels = new Map<number, string>();
  const labelBranchRe = /if\s*\(\s*id\s*==\s*(\d+)\s*\)\s*\{\s*return\s+Rez\.Strings\.(\w+)\s*;/g;
  while ((m = labelBranchRe.exec(labelBody))) {
    labels.set(parseInt(m[1], 10), m[2]);
  }
  const labelTail = labelBody.replace(labelBranchRe, "");
  const defaultLabel = /return\s+Rez\.Strings\.(\w+)\s*;/.exec(labelTail);
  if (defaultLabel) labels.set(0, defaultLabel[1]);

  // Resolve resource ids against strings.xml.
  const xml = readSource(STRINGS_XML);
  const stringMap: Record<string, string> = {};
  const stringRe = /<string\s+id="(\w+)">([^<]*)<\/string>/g;
  while ((m = stringRe.exec(xml))) {
    stringMap[m[1]] = m[2];
  }

  const result: SupportedLoc[] = [];
  for (let id = 0; id < count; id++) {
    const block = blocks.get(id);
    const labelRes = labels.get(id);
    if (!block || !labelRes) {
      console.error(`warning: id ${id} missing from get() or settingsLabelRes()`);
      continue;
    }
    result.push({
      id,
      ...block,
      labelRes,
      label: stringMap[labelRes] ?? `<missing string: ${labelRes}>`,
    });
  }
  return result;
}

function main(): void {
  const locs = parseLocations();
  console.log(`${locs.length} supported locations (parsed from Locations.mc + strings.xml):\n`);

  type Col = { hdr: string; get: (l: SupportedLoc) => string; w: number };
  const cols: Col[] = [
    { hdr: "id",      get: (l) => String(l.id),         w: 2  },
    { hdr: "label",   get: (l) => l.label,              w: 38 },
    { hdr: "name",    get: (l) => l.name,               w: 12 },
    { hdr: "slug",    get: (l) => l.locationSlug,       w: 12 },
    { hdr: "rwsCode", get: (l) => l.rwsCode,            w: 22 },
    { hdr: "lat",     get: (l) => l.lat.toFixed(6),     w: 9  },
    { hdr: "lon",     get: (l) => l.lon.toFixed(6),     w: 9  },
  ];
  const sep = "  ";
  console.log("  " + cols.map((c) => c.hdr.padEnd(c.w)).join(sep));
  console.log("  " + cols.map((c) => "-".repeat(c.w)).join(sep));
  for (const loc of locs) {
    console.log("  " + cols.map((c) => c.get(loc).padEnd(c.w)).join(sep));
  }
}

main();
