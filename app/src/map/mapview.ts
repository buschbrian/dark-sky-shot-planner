import { Protocol } from "pmtiles";
import maplibregl, { type Map as MapLibreMap } from "maplibre-gl";

/**
 * The map is an enhancement, never the interface. It initializes lazily and
 * never takes programmatic focus; every state in the app is completable
 * without touching it.
 */

let initialized = false;
let map: MapLibreMap | null = null;

export function initMap(
  container: HTMLElement,
  dataUrls: { lp?: string; land?: string; places?: string },
): MapLibreMap {
  if (initialized && map) return map;
  const protocol = new Protocol();
  maplibregl.addProtocol("pmtiles", protocol.tile);

  map = new maplibregl.Map({
    container,
    style: {
      version: 8,
      sources: {},
      layers: [
        {
          id: "bg",
          type: "background",
          paint: { "background-color": "#0b0e14" },
        },
      ],
    },
    center: [-111.5, 39.5],
    zoom: 5,
    attributionControl: false,
    interactive: true,
    keyboard: false,
  });

  map.on("load", () => {
    if (!map) return;
    if (dataUrls.lp) addLightPollution(map, dataUrls.lp);
    if (dataUrls.land) addLandOwnership(map, dataUrls.land);
    if (dataUrls.places) addPlaces(map, dataUrls.places);
  });

  initialized = true;
  return map;
}

export function getMap(): MapLibreMap | null {
  return map;
}

function addLightPollution(m: MapLibreMap, url: string): void {
  m.addSource("lp", { type: "raster", url: `pmtiles://${url}` });
  m.addLayer({
    id: "lp-layer",
    type: "raster",
    source: "lp",
    paint: { "raster-opacity": 0.9 },
  });
}

function addLandOwnership(m: MapLibreMap, url: string): void {
  m.addSource("land", { type: "vector", url: `pmtiles://${url}` });
  m.addLayer(
    {
      id: "land-fill",
      type: "fill",
      source: "land",
      "source-layer": "padus",
      paint: { "fill-color": ["get", "color"], "fill-opacity": 0.25 },
    },
    undefined,
  );
  m.addLayer(
    {
      id: "land-line",
      type: "line",
      source: "land",
      "source-layer": "padus",
      paint: { "line-color": ["get", "color"], "line-width": 1 },
    },
    undefined,
  );
}

function addPlaces(m: MapLibreMap, url: string): void {
  m.addSource("places", { type: "geojson", data: url });
  m.addLayer({
    id: "places-circle",
    type: "circle",
    source: "places",
    paint: {
      "circle-radius": 6,
      "circle-color": "#ffd54d",
      "circle-stroke-color": "#ffffff",
      "circle-stroke-width": 1,
    },
  });
}

export function setLayerVisible(layerId: string, visible: boolean): void {
  if (!map) return;
  const ids: Record<string, string[]> = {
    lp: ["lp-layer"],
    land: ["land-fill", "land-line"],
    places: ["places-circle"],
  };
  for (const id of ids[layerId] ?? []) {
    if (map.getLayer(id)) {
      map.setLayoutProperty(id, "visibility", visible ? "visible" : "none");
    }
  }
}
