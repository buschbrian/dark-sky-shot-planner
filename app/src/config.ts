/**
 * Typed view of the pipeline-emitted config and manifests. Nothing about
 * the data sources is hardcoded here; everything comes from files the
 * pipelines publish.
 */

export interface RadianceBreakpointJson {
  radiance: number;
  color: string;
  label: string;
}

export interface ManagerClassJson {
  key: string;
  label: string;
  color: string;
}

export interface AppConfigJson {
  version: number;
  aoi: {
    name: string;
    states: string[];
    bbox: Bbox;
  };
  gc_min_useful_altitude_deg: number;
  freshness_days: Record<string, LayerFreshnessCfg>;
  radiance_mapping: {
    source: string;
    source_year: number;
    unit: string;
    breakpoints: RadianceBreakpointJson[];
  };
  manager_taxonomy: ManagerClassJson[];
}

export interface Bbox {
  west: number;
  south: number;
  east: number;
  north: number;
}

interface LayerFreshnessCfg {
  layer_id: string;
  fresh_max_days: number;
  aging_max_days: number;
  stale_max_days: number;
}

export interface ManifestJson {
  layer_id: string;
  source_name: string;
  source_url: string;
  license: string;
  license_url: string;
  retrieval_utc: string;
  publication_date: string | null;
  counts: Record<string, number>;
}
