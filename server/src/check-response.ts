#!/usr/bin/env node

const args = process.argv.slice(2);
const local = args.includes("--local") || args.includes("-l");
const base = local ? "http://localhost:31415" : "https://ows.j0r1s.nl";
const url = `${base}/conditions/vlissingen`;

(async (): Promise<void> => {
  const res = await fetch(url);
  const body = await res.text();
  const bytes = Buffer.byteLength(body, "utf8");

  process.stdout.write(body);
  if (!body.endsWith("\n")) process.stdout.write("\n");

  console.error(`\n${url}`);
  console.error(`HTTP ${res.status}`);
  console.error(`${bytes} bytes (${(bytes / 1024).toFixed(2)} KB)`);
})().catch((err: Error) => {
  console.error(`fetch failed: ${err.message}`);
  process.exit(1);
});
