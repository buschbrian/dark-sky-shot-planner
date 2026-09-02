import "../style.css";

import { planNight, type NightReport } from "./astronomy/planner";
import {
  fetchCloudForecast,
  averageCloudCover,
  type CloudForecast,
} from "./weather/openmeteo";
import { freshnessOf, FRESHNESS_LABEL, type Freshness } from "./freshness";
import { initMap, setLayerVisible, getMap } from "./map/mapview";
import { dataUrl } from "./paths";
import { classifyRadiance, sampleRadiance, type LowResGrid } from "./radiance";
import { parseUrlState, updateUrlState, type UrlState } from "./state/urlstate";
import { renderAnswer, renderAnswerError } from "./ui/answer";
import type { AppConfigJson, DataStatusJson, ManifestJson } from "./config";

interface AppData {
  /** null when config.json could not be fetched — the app degrades, it does not die. */
  config: AppConfigJson | null;
  radianceGrid: LowResGrid | null;
  lpYear: number | null;
  manifests: Record<string, ManifestJson>;
  /** null when data-status.json is absent (a build that predates it). */
  dataStatus: DataStatusJson | null;
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

async function fetchJson<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

async function loadData(): Promise<AppData> {
  // Every artifact is optional at load time. The astronomy — the headline
  // number — is computed in the browser and must keep working even when the
  // published data layers are missing, stale, or half-deployed.
  const config = await fetchJson<AppConfigJson>(dataUrl("config.json"));
  const manifests: Record<string, ManifestJson> = {};
  for (const dir of ["light_pollution", "padus", "darksky_places"]) {
    const manifest = await fetchJson<ManifestJson>(dataUrl(`${dir}/manifest.json`));
    // manifest missing: the provenance panel will say so
    if (manifest) manifests[dir] = manifest;
  }
  const dataStatus = await fetchJson<DataStatusJson>(dataUrl("data-status.json"));
  // brightness row simply won't render when this is absent — and it must not
  // render from a fixture either: a synthetic grid is not a sky-brightness
  // reading, so a fixture build withholds the number rather than fake one.
  const radianceGrid = isFixture(dataStatus, "light_pollution")
    ? null
    : await fetchJson<LowResGrid>(dataUrl("light_pollution/radiance-grid-lowres.json"));
  return {
    config,
    radianceGrid,
    lpYear: config?.radiance_mapping.source_year ?? null,
    manifests,
    dataStatus,
  };
}

function isFixture(status: DataStatusJson | null, layerId: string): boolean {
  return status?.layers[layerId] === "fixture";
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
  // Without the radiance mapping from config.json a raw radiance number cannot
  // be labelled honestly, so we withhold the row rather than guess at a class.
  const radiance =
    appData?.radianceGrid != null && appData.config != null
      ? sampleRadiance(appData.radianceGrid, state.lat, state.lon)
      : null;

  renderAnswer(answerEl, {
    report,
    lat: state.lat,
    lon: state.lon,
    gcMinAltDeg: appData?.config?.gc_min_useful_altitude_deg ?? 12,
    radianceAtPoint: {
      value: radiance,
      year: appData?.lpYear ?? 0,
      label:
        radiance !== null && appData?.config
          ? classifyRadiance(radiance, appData.config)
          : "unknown",
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
  if (!map || !map.getLayer("land-fill") || !appData?.config) return null;
  // Sample PAD-US polygons are not a land manager; never name one from them.
  if (isFixture(appData.dataStatus, "land_ownership")) return null;
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
    const manifest = appData?.manifests[manifestKey];
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
    // Thresholds come from config.json; with no config we cannot judge age, and
    // saying so beats inventing a threshold the maintainer never chose.
    const cfg = appData?.config?.freshness_days[layerId] ?? null;
    const fresh: Freshness = cfg
      ? freshnessOf(manifest?.publication_date ?? null, { ...cfg, layer_id: layerId })
      : "unavailable";
    tdFresh.textContent = `${FRESHNESS_LABEL[fresh]}${layerId === "darksky_places" ? "; manually curated, not exhaustive" : ""}${isFixture(appData?.dataStatus ?? null, layerId) ? "; SAMPLE FIXTURE — not real coverage" : ""}`;
    tr.append(tdName, tdSource, tdPub, tdFresh);
    table.append(tr);
  }
  el.append(table);

  if (!appData?.config) {
    const warn = document.createElement("p");
    warn.className = "hint";
    warn.textContent =
      "config.json could not be loaded, so sky-brightness classes, land-manager labels, and freshness thresholds are unavailable. Darkness and Galactic Center times are computed in your browser and are unaffected.";
    el.append(warn);
  }
}

/**
 * A deploy without the real-data refresh serves offline fixtures for the map
 * layers. Say so where the user will see it, not only in a collapsed panel.
 */
function renderDataNotice(): void {
  const el = $("data-notice");
  const fixtures = Object.entries(appData?.dataStatus?.layers ?? {})
    .filter(([, origin]) => origin === "fixture")
    .map(([layerId]) => layerId.replace("_", " "));
  if (fixtures.length === 0) {
    el.hidden = true;
    return;
  }
  el.textContent =
    `Sample data: the ${fixtures.join(" and ")} map layer${fixtures.length > 1 ? "s are" : " is"} ` +
    "an offline fixture, not real coverage. Darkness, moon, and Galactic Center times are computed " +
    "in your browser and are unaffected. See docs/credentials-setup.md to enable the real layers.";
  el.hidden = false;
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

  try {
    appData = await loadData();
  } catch (err) {
    // The published artifacts are an enhancement. Losing them must never cost
    // the user the answer, which is computed client-side.
    console.error("app data unavailable; continuing in degraded mode", err);
    appData = null;
  }

  applyState(parseUrlState(location.hash));
  renderProvenance();
  renderDataNotice();

  $("coord-apply").addEventListener("click", computeAndRender);
  $("coord-input").addEventListener("change", computeAndRender);
  $("date-input").addEventListener("change", computeAndRender);
  for (const id of LAYER_CHECKBOX_IDS) check(id).addEventListener("change", computeAndRender);

  const mapContainer = $("map");
  initMap(mapContainer, {
    lp: dataUrl("light_pollution/light-pollution.pmtiles"),
    land: dataUrl("padus/padus.pmtiles"),
    places: dataUrl("darksky_places/darksky-places.geojson"),
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
