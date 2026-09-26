/**
 * Renders the conditions Worker's multi-model cloud-cover picture: one line
 * per model, the run time and its freshness (ADR-0006 wording via
 * `hourFreshnessOf`), and disagreement shown rather than averaged away. Text
 * first, no framework (ADR-0001) — plain DOM nodes, same as `ui/answer.ts`.
 */
import type { ConditionsField, ConditionsResponse } from "../weather/conditions";
import { summarizeFieldByModel } from "../weather/conditions";
import { FRESHNESS_LABEL, hourFreshnessOf, type HourFreshnessConfig } from "../freshness";

const DEFAULT_WEATHER_FRESHNESS: HourFreshnessConfig = {
  layer_id: "weather_forecast",
  fresh_max_hours: 12,
  aging_max_hours: 24,
  stale_max_hours: 48,
};

export interface ConditionsPanelContext {
  response: ConditionsResponse;
  /** From config.json's freshness_hours.weather_forecast; falls back to the documented default. */
  freshnessCfg?: HourFreshnessConfig;
  now?: Date;
}

const MODEL_LABELS: Record<string, string> = {
  hrrr: "HRRR (NOAA, 3 km)",
  gfs: "GFS (NOAA, global)",
  icon: "ICON (DWD, global)",
  ecmwf: "ECMWF IFS (global)",
  gem: "GEM (ECCC, regional)",
  ukmo: "UKMO global",
};

function modelLabel(model: string): string {
  return MODEL_LABELS[model] ?? model;
}

const runTimeFmt = new Intl.DateTimeFormat([], {
  hour: "2-digit",
  minute: "2-digit",
  month: "short",
  day: "numeric",
  timeZone: "UTC",
});

function fmtRunTime(iso: string | null): string {
  if (!iso) return "run time unavailable";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "run time unavailable";
  return `${runTimeFmt.format(d)} UTC`;
}

/** One <dl> row per model for a single field (e.g. cloud_cover_total). */
function renderFieldRows(
  field: ConditionsField | undefined,
  freshnessCfg: HourFreshnessConfig,
  now: Date,
): HTMLElement[] {
  const rows = summarizeFieldByModel(field);
  return rows.map((row) => {
    const dt = document.createElement("dt");
    dt.textContent = modelLabel(row.model);
    const dd = document.createElement("dd");
    if (row.status === "unavailable") {
      dd.textContent = `unavailable${row.reason ? ` (${row.reason})` : ""}`;
    } else {
      const fresh = hourFreshnessOf(
        row.modelRunUtc,
        field?.fetched_utc ?? null,
        freshnessCfg,
        now,
      );
      const pct = row.meanPct === null ? "unavailable" : `${row.meanPct}%`;
      dd.textContent =
        `${pct} — run ${fmtRunTime(row.modelRunUtc)} (${FRESHNESS_LABEL[fresh]})`;
    }
    return [dt, dd];
  }).flat();
}

/**
 * Renders the multi-model cloud-cover band into `el`. Shows total, low, mid,
 * high cover, one line per model, plus each model's run age. Disagreement
 * between models is the point — this never collapses the series into one
 * blended number.
 */
export function renderConditionsPanel(el: HTMLElement, ctx: ConditionsPanelContext): void {
  el.replaceChildren();
  const freshnessCfg = ctx.freshnessCfg ?? DEFAULT_WEATHER_FRESHNESS;
  const now = ctx.now ?? new Date();

  const heading = document.createElement("p");
  heading.className = "hint";
  heading.textContent = "Multi-model cloud cover for tonight's dark window (Worker):";
  el.append(heading);

  const sections: [string, string][] = [
    ["cloud_cover_total", "Total cloud cover"],
    ["cloud_cover_low", "Low cloud"],
    ["cloud_cover_mid", "Mid cloud"],
    ["cloud_cover_high", "High cloud"],
  ];

  for (const [key, label] of sections) {
    const field = ctx.response.fields[key];
    const h = document.createElement("h4");
    h.textContent = label;
    el.append(h);
    if (!field || field.status === "unavailable") {
      const p = document.createElement("p");
      p.className = "hint";
      p.textContent = `unavailable${field?.reason ? ` (${field.reason})` : ""}`;
      el.append(p);
      continue;
    }
    const dl = document.createElement("dl");
    dl.className = "answer-grid";
    dl.append(...renderFieldRows(field, freshnessCfg, now));
    el.append(dl);
  }

  if (ctx.response.attribution?.length) {
    const attr = document.createElement("p");
    attr.className = "hint";
    attr.textContent = ctx.response.attribution.join(" · ");
    el.append(attr);
  }
}

/** Shown when the Worker failed and the app fell back to direct Open-Meteo. */
export function renderConditionsFallback(el: HTMLElement, reason: string): void {
  el.replaceChildren();
  const p = document.createElement("p");
  p.className = "hint";
  p.textContent = `Live multi-model conditions unavailable (${reason}) — showing the direct Open-Meteo forecast instead.`;
  el.append(p);
}
