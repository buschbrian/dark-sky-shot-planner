/** Maps an upstream URL to its fixture name. Shared by the recorder and the test router. */
export function fixtureName(raw: string): string {
  const u = new URL(raw);
  const p = decodeURIComponent(u.pathname);
  const meta = /^\/data\/([^/]+)\/static\/meta\.json$/.exec(p);
  if (meta) return `open-meteo-meta-${meta[1]}`;
  if (u.hostname === "api.open-meteo.com" && p === "/v1/forecast") {
    return `open-meteo-forecast-${u.searchParams.get("models")}`;
  }
  if (u.hostname === "air-quality-api.open-meteo.com") return "open-meteo-air-quality";
  const ndgd = /\/ndgd_smoke_(sfc|vert)_1hr_avg_time\/ImageServer\/identify$/.exec(p);
  if (ndgd) return `ndgd-smoke-${ndgd[1]}-identify`;
  if (u.hostname === "www.7timer.info") return "7timer-astro";
  if (p.endsWith("/noaa-planetary-k-index.json")) return "swpc-kp";
  if (p.endsWith("/noaa-planetary-k-index-forecast.json")) return "swpc-kp-forecast";
  if (p.endsWith("/ovation_aurora_latest.json")) return "swpc-ovation";
  if (p.includes("NOAA_Satellite_Smoke_Detection")) {
    return u.searchParams.has("outStatistics") ? "hms-stats" : "hms-query";
  }
  if (u.hostname === "www.airnowapi.org") return "airnow-ziplatlong";
  throw new Error(`no fixture name for ${u.hostname}${p}`);
}

/** Drops anything that could be a credential before a URL is written to disk. */
export function sanitizeUrl(raw: string): string {
  const u = new URL(raw);
  for (const k of [...u.searchParams.keys()]) {
    if (/key|token|secret|password/i.test(k)) u.searchParams.set(k, "REDACTED");
  }
  return u.toString();
}

export interface Fixture {
  url: string;
  status: number;
  content_type: string;
  body_format: "json" | "text";
  body: unknown;
  synthetic?: boolean;
  note?: string;
}
