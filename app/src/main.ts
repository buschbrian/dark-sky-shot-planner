import "../style.css";

import { planNight, type NightReport } from "./astronomy/planner";
import {
  fetchCloudForecast,
  averageCloudCover,
  type CloudForecast,
} from "./weather/openmeteo";
import { freshnessOf, FRESHNESS_LABEL, type LayerFreshnessConfig } from "./freshness";
import { initMap, setLayerVisible, getMap } from "./map/mapview";
import { classifyRadiance, sampleRadiance, type LowResGrid } from "./radiance";
import { parseUrlState, updateUrlState, type UrlState } from "./state/urlstate";
import { renderAnswer, renderAnswerError } from "./ui/answer";
import type { AppConfigJson, ManifestJson } from "./config";

interface AppData {
  config: AppConfigJson;
  radianceGrid: LowResGrid | null;
  lpYear: number;
  manifests: Record<string, ManifestJson>;
}

const $ = <T extends HTMLElement>(id: string): T => {
  const el = document.getElementById(id);
  if (!el) throw new Error(`missing #${id}`);
  return el as T;
};
const input = (id: string): HTMLInputElement => $(id);
const check = (id: string): HTMLInputElement => $(id);

const LAYER_CHECKBOX_IDS = ["layer-lp", "layer-land", "layer-places"] as const;
const LAYER_VALUES = ["lp", "land", "places"] as const;

let appData: AppData | null = null;

async function loadData(): Promise<AppData> {
  const config = (await (await fetch("/config.json")).json()) as AppConfigJson;
  const manifests: Record<string, ManifestJson> = {};
  for (const dir of ["light_pollution", "padus", "darksky_places"]) {
    try {
      manifests[dir] = (await (await fetch(`/${dir}/manifest.json`)).json()) as ManifestJson;
    } catch {
      /* manifest missing: provenance panel will say so */
    }
  }
  let radianceGrid: LowResGrid | null = null;
  try {
    radianceGrid = (await (
      await fetch("/light_pollution/radiance-grid-lowres.json")
    ).json()) as LowResGrid;
  } catch {
    /* brightness row simply won't render */
  }
  return {
    config,
    radianceGrid,
    lpYear: config.radiance_mapping.source_year,
    manifests,
  };
}

function currentState(): UrlState {
  let lat: number | null = null;
  let lon: number | null = null;
  const m = input("coord-input").value.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
  if (m?.[1] && m[2]) {
    lat = Number(m[1]);
    lon = Number(m[2]);
  }
  const date = input("date-input").value || null;
  const layers = LAYER_CHECKBOX_IDS.flatMap((id, i) =>
    check(id).checked ? [LAYER_VALUES[i]!] : [],
  );
  return {
    lat,
    lon,
    date,
    layers,
  };
}

function applyState(state: UrlState): void {
  if (state.lat !== null && state.lon !== null) {
    input("coord-input").value = `${state.lat}, ${state.lon}`;
  }
  if (state.date) input("date-input").value = state.date;
  else input("date-input").value = new Date().toISOString().slice(0, 10);
  for (const [i, id] of LAYER_CHECKBOX_IDS.entries()) {
    check(id).checked = state.layers.includes(LAYER_VALUES[i]!);
  }
}

/** The local evening at 21:00 on `isoDate`, as a UTC Date. */
function eveningUtcFor(isoDate: string): Date {
  // Constructed in local time deliberately: "the night of the 22nd" is a
  // local notion. The astronomy math works in UTC internally.
  return new Date(`${isoDate}T21:00:00`);
}

async function computeAndRender(): Promise<void> {
  const state = currentState();
  updateUrlState(state);
  syncLayers(state.layers);

  const answerEl = $("answer");
  if (state.lat === null || state.lon === null) {
    renderAnswerError(answerEl, "Enter a location to see the answer.");
    return;
  }
  const dateIso = state.date ?? new Date().toISOString().slice(0, 10);

  let report: NightReport;
  try {
    report = planNight({
      latitude: state.lat,
      longitude: state.lon,
      eveningUtc: eveningUtcFor(dateIso),
    });
  } catch (err) {
    renderAnswerError(answerEl, `Could not compute night plan: ${String(err)}`);
    return;
  }

  const landManager = lookupLandManager(state.lat, state.lon);
  const radiance =
    appData?.radianceGrid != null
      ? sampleRadiance(appData.radianceGrid, state.lat, state.lon)
      : null;

  renderAnswer(answerEl, {
    report,
    lat: state.lat,
    lon: state.lon,
    gcMinAltDeg: appData?.config.gc_min_useful_altitude_deg ?? 12,
    radianceAtPoint: {
      value: radiance,
      year: appData?.lpYear ?? 0,
      label:
        radiance !== null && appData ? classifyRadiance(radiance, appData.config) : "unknown",
    },
    landManager,
    cloudPct: null,
    cloudAttribution: null,
  });

  $("location-status").textContent = `Planning ${state.lat.toFixed(4)}, ${state.lon.toFixed(4)} on ${dateIso}.`;

  // Weather is fetched on demand and updates the answer when it arrives.
  void fetchWeatherAndUpdate(state.lat, state.lon, report);
}

async function fetchWeatherAndUpdate(
  lat: number,
  lon: number,
  report: NightReport,
): Promise<void> {
  let forecast: CloudForecast;
  try {
    forecast = await fetchCloudForecast(lat, lon);
  } catch {
    const status = $("location-status");
    status.textContent += " Cloud forecast unavailable right now.";
    return;
  }
  if (!report.darkness) return;
  const pct = averageCloudCover(forecast, report.darkness.start, report.darkness.end);
  if (pct === null) return;
  const dd = document.createElement("dd");
  dd.textContent = `${pct}% average over the moon-free window`;
  const dt = document.createElement("dt");
  dt.textContent = "Cloud cover forecast";
  document.querySelector(".answer-grid")?.append(dt, dd);
  void forecast;
}

function lookupLandManager(
  lat: number,
  lon: number,
): { label: string; agencyUrl: string | null } | null {
  const map = getMap();
  if (!map || !map.getLayer("land-fill") || !appData) return null;
  const pt = map.project([lon, lat]);
  const features = map.queryRenderedFeatures([pt.x, pt.y], { layers: ["land-fill"] });
  const key = features[0]?.properties?.manager as string | undefined;
  if (!key) return null;
  const cls = appData.config.manager_taxonomy.find((c) => c.key === key);
  return cls ? { label: cls.label, agencyUrl: agencyUrl(key) } : null;
}

const AGENCY_URLS: Record<string, string> = {
  federal_blm: "https://www.blm.gov/visit",
  federal_usfs: "https://www.fs.usda.gov/recreate",
  federal_nps: "https://www.nps.gov/planyourvisit/",
  federal_other: "https://www.usa.gov/federal-agencies",
  state: "https://www.recreation.gov/",
};

function agencyUrl(key: string): string | null {
  return AGENCY_URLS[key] ?? null;
}

function syncLayers(layers: string[]): void {
  for (const id of LAYER_VALUES) setLayerVisible(id, layers.includes(id));
}

function renderProvenance(): void {
  const el = $("provenance");
  if (!appData) return;
  el.replaceChildren();
  const table = document.createElement("table");
  const head = document.createElement("tr");
  for (const h of ["Layer", "Source", "Publication date", "Status"]) {
    const th = document.createElement("th");
    th.textContent = h;
    head.append(th);
  }
  table.append(head);
  const rowsDef: [string, string][] = [
    ["light_pollution", "light_pollution"],
    ["land_ownership", "padus"],
    ["darksky_places", "darksky_places"],
  ];
  for (const [layerId, manifestKey] of rowsDef) {
    const manifest = appData.manifests[manifestKey];
    const tr = document.createElement("tr");
    const tdName = document.createElement("td");
    tdName.textContent = layerId.replace("_", " ");
    const tdSource = document.createElement("td");
    if (manifest) {
      const a = document.createElement("a");
      a.href = manifest.source_url;
      a.textContent = manifest.source_name;
      tdSource.append(a);
    } else {
      tdSource.textContent = "manifest missing";
    }
    const tdPub = document.createElement("td");
    tdPub.textContent = manifest?.publication_date ?? "—";
    const tdFresh = document.createElement("td");
    const cfg: LayerFreshnessConfig =
      appData.config.freshness_days[layerId] ??
      ({ ...appData.config.freshness_days.land_ownership!, layer_id: layerId } as LayerFreshnessConfig);
    const fresh = freshnessOf(manifest?.publication_date ?? null, cfg);
    tdFresh.textContent = `${FRESHNESS_LABEL[fresh]}${layerId === "darksky_places" ? "; manually curated, not exhaustive" : ""}`;
    tr.append(tdName, tdSource, tdPub, tdFresh);
    table.append(tr);
  }
  el.append(table);
}

function applyTheme(theme: string): void {
  document.body.dataset.theme = theme;
  localStorage.setItem("theme", theme);
}

async function boot(): Promise<void> {
  applyTheme(localStorage.getItem("theme") ?? "dark");

  const savedTheme = $("theme-select") as HTMLSelectElement;
  savedTheme.value = document.body.dataset.theme ?? "dark";
  savedTheme.addEventListener("change", () => applyTheme(savedTheme.value));

  appData = await loadData();

  applyState(parseUrlState(location.hash));
  renderProvenance();

  $("coord-apply").addEventListener("click", computeAndRender);
  $("coord-input").addEventListener("change", computeAndRender);
  $("date-input").addEventListener("change", computeAndRender);
  for (const id of LAYER_CHECKBOX_IDS) check(id).addEventListener("change", computeAndRender);

  const mapContainer = $("map");
  initMap(mapContainer, {
    lp: "/light_pollution/light-pollution.pmtiles",
    land: "/padus/padus.pmtiles",
    places: "/darksky_places/darksky-places.geojson",
  });
  getMap()?.on("click", (e) => {
    input("coord-input").value = `${e.lngLat.lat.toFixed(5)}, ${e.lngLat.lng.toFixed(5)}`;
    void computeAndRender();
  });

  window.addEventListener("hashchange", () => {
    applyState(parseUrlState(location.hash));
    void computeAndRender();
  });

  await computeAndRender();
}

void boot();
