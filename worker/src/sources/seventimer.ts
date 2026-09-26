import { getText, isRecord, num, parseJson, UpstreamError } from "../http.ts";
import { type Cell, cellKey, inWindow, type Window } from "../params.ts";
import { cachedLoad, edgeStore, type Loaded } from "../store.ts";
import { type Deps, type Env, type Field, iso, type Series } from "../types.ts";
import { assembleField } from "./openmeteo.ts";

export const SEVENTIMER_URL = "https://www.7timer.info/bin/astro.php";
export const SEVENTIMER_SOURCE = "7Timer! ASTRO (Shanghai Astronomical Observatory)";
const MISSING = -9999;

export interface Astro {
  init_utc: string;
  points: { t: string; seeing: number | null; transparency: number | null }[];
}

export function parseAstro(text: string): Astro {
  const body = parseJson(text);
  if (!isRecord(body) || !Array.isArray(body.dataseries)) {
    throw new UpstreamError("unexpected response shape");
  }
  const m = /^(\d{4})(\d{2})(\d{2})(\d{2})$/.exec(String(body.init ?? ""));
  if (!m) throw new UpstreamError("unexpected init format");
  const init = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]));
  const index = (x: unknown) => {
    const v = num(x);
    return v === null || v === MISSING || v < 1 || v > 8 ? null : v;
  };
  const points = body.dataseries.flatMap((row) => {
    if (!isRecord(row)) return [];
    const h = num(row.timepoint);
    if (h === null) return [];
    return [
      {
        t: iso(new Date(init + h * 3_600_000)),
        seeing: index(row.seeing),
        transparency: index(row.transparency),
      },
    ];
  });
  return { init_utc: iso(new Date(init)), points };
}

const FIELDS = [
  { field: "seeing", key: "seeing" },
  { field: "transparency", key: "transparency" },
] as const;

function toSeries(
  loaded: Loaded<Astro> | { ok: false; reason: string; last_good: null },
  key: "seeing" | "transparency",
  window: Window,
): Series {
  const base = { model: "7timer_astro", upstream_model: "GFS via 7Timer! ASTRO" };
  const pick = (a: Astro) =>
    a.points.filter((p) => inWindow(p.t, window)).map((p) => ({ t: p.t, v: p[key] }));
  if (!loaded.ok) {
    const lg = loaded.last_good;
    return {
      ...base,
      model_run_utc: lg?.data.init_utc ?? null,
      fetched_utc: null,
      status: "unavailable",
      reason: loaded.reason,
      last_good_utc: lg?.fetched_utc ?? null,
      values: lg ? pick(lg.data) : [],
    };
  }
  const values = pick(loaded.entry.data);
  const ok = values.some((p) => p.v !== null);
  return {
    ...base,
    model_run_utc: loaded.entry.data.init_utc,
    fetched_utc: loaded.entry.fetched_utc,
    status: ok ? "ok" : "unavailable",
    ...(ok ? {} : { reason: "no 7Timer forecast covers this window", last_good_utc: null }),
    values: ok ? values : [],
  };
}

export async function sevenTimerFields(
  deps: Deps,
  env: Env,
  cell: Cell,
  window: Window,
): Promise<Record<string, Field>> {
  const enabled = (env.SEVENTIMER_ENABLED ?? "true").toLowerCase() !== "false";
  const loaded = enabled
    ? await cachedLoad(
        deps,
        {
          store: edgeStore(deps),
          source: "7timer",
          key: `7timer:${cellKey(cell)}`,
          ttlSeconds: 3 * 3600,
        },
        async () => {
          const url = `${SEVENTIMER_URL}?lon=${cell.lon}&lat=${cell.lat}&ac=0&unit=metric&output=json&tzshift=0`;
          const { status, text } = await getText(deps.fetch, url, 10_000);
          if (status < 200 || status >= 300) throw new UpstreamError(`HTTP ${status}`);
          const data = parseAstro(text);
          return { data, model_run_utc: data.init_utc };
        },
      )
    : ({ ok: false, reason: "disabled by configuration", last_good: null } as const);
  const out: Record<string, Field> = {};
  for (const { field, key } of FIELDS) {
    out[field] = assembleField(
      "index 1–8 (1 best)",
      SEVENTIMER_SOURCE,
      [toSeries(loaded, key, window)],
      {
        terms: "non-commercial use only",
        optional: true,
      },
    );
  }
  return out;
}
