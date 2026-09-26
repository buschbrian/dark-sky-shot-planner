/**
 * Records real upstream responses ONCE for the offline tests: `npm run record-fixtures`.
 * It drives the Worker's own handler with a recording fetch, so every fixture matches a URL
 * the code really builds. No key is used; AirNow is recorded keyless (its 401 is the "down"
 * fixture) and its happy-path fixture is synthetic. Re-recording rewrites test/fixtures/recorded.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { handle } from "../src/index.ts";
import { type Fixture, fixtureName, sanitizeUrl } from "./fixture-names.ts";

const CELL = { lat: 38.35, lon: -109.95 };
const BBOX = "-125,30,-100,50";
const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, "..", "test", "fixtures", "recorded");
const downDir = join(here, "..", "test", "fixtures", "down");

const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
const start = process.argv[2] ?? `${tomorrow}T00:00Z`;
const end = process.argv[3] ?? `${tomorrow}T14:00Z`;

const recorded = new Map<string, Fixture>();

async function capture(
  url: string,
  init?: RequestInit,
): Promise<{ fixture: Fixture; res: Response }> {
  const res = await fetch(url, init);
  const text = await res.text();
  let body: unknown = text;
  let body_format: Fixture["body_format"] = "text";
  try {
    body = JSON.parse(text);
    body_format = "json";
  } catch {
    // Keep as text.
  }
  const fixture: Fixture = {
    url: sanitizeUrl(url),
    status: res.status,
    content_type: res.headers.get("content-type") ?? "",
    body_format,
    body,
  };
  return { fixture, res: new Response(text, { status: res.status, headers: res.headers }) };
}

const recordingFetch = async (input: string, init?: RequestInit): Promise<Response> => {
  const { fixture, res } = await capture(input, init);
  recorded.set(fixtureName(input), fixture);
  return res;
};

type Trim = (body: unknown) => unknown;

const TRIM: Record<string, Trim> = {
  // ~1 MB global grid → the Mountain West slice the tests use.
  "swpc-ovation": (b) => {
    const o = b as { coordinates: [number, number, number][] };
    return {
      ...o,
      coordinates: o.coordinates.filter(
        ([lon, lat]) => lat >= 30 && lat <= 70 && lon >= 230 && lon <= 270,
      ),
    };
  },
  "hms-query": (b) => {
    const fc = b as { features: { geometry: { coordinates: unknown } }[] };
    const size = (f: { geometry: { coordinates: unknown } }) =>
      JSON.stringify(f.geometry.coordinates).length;
    return { ...fc, features: [...fc.features].sort((a, z) => size(a) - size(z)).slice(0, 12) };
  },
};

async function main(): Promise<void> {
  const deps = { fetch: recordingFetch, now: () => new Date(), cache: null };
  const env = { SEVENTIMER_ENABLED: "true" };
  const base = "https://worker.local";
  const q = `lat=${CELL.lat}&lon=${CELL.lon}`;
  const calls = [
    `/v1/conditions?${q}&start=${start}&end=${end}`,
    `/v1/space-weather?${q}`,
    `/v1/smoke?bbox=${BBOX}`,
  ];
  for (const path of calls) {
    const res = await handle(new Request(base + path), env, deps);
    console.log(res.status, path);
  }

  mkdirSync(outDir, { recursive: true });
  mkdirSync(downDir, { recursive: true });
  const files: Record<string, { url: string; status: number; bytes: number }> = {};
  for (const [name, fixture] of recorded) {
    const trim = TRIM[name];
    const out = trim
      ? { ...fixture, body: trim(fixture.body), note: "trimmed by record-fixtures" }
      : fixture;
    const text = `${JSON.stringify(out, null, 1)}\n`;
    writeFileSync(join(outDir, `${name}.json`), text);
    files[name] = { url: out.url, status: out.status, bytes: text.length };
  }

  // Real keyless AirNow answer: the "down" (unauthenticated) fixture. No key is sent.
  const airnow = await capture(
    `https://www.airnowapi.org/aq/observation/current/ziplatLong/?format=application/json&latitude=${CELL.lat}&longitude=${CELL.lon}&distance=50`,
  );
  writeFileSync(
    join(downDir, "airnow-ziplatlong.json"),
    `${JSON.stringify({ ...airnow.fixture, note: "real keyless response" }, null, 1)}\n`,
  );

  writeFileSync(
    join(outDir, "..", "manifest.json"),
    `${JSON.stringify(
      {
        recorded_utc: new Date().toISOString(),
        cell: CELL,
        window: { start, end },
        bbox: BBOX,
        files,
      },
      null,
      1,
    )}\n`,
  );
  console.log(`recorded ${recorded.size} fixtures`);
}

await main();
