/**
 * The hand-curated companion to the computed sky events.
 *
 * Meteor showers, festivals and one-off happenings cannot be derived from
 * ephemeris: somebody has to read a page and write down what it said. That
 * makes this the same kind of artifact as `config/darksky-places.csv` and it
 * carries the same contract — every row has a `source_url`, and a
 * `verified_on` date or an explicit null that the UI shows as unverified. The
 * cited sites are never scraped. ADR-0008.
 *
 * The file is bundled at build time rather than fetched: it is small, it is
 * versioned in git next to the code that reads it, and unlike the pipeline
 * artifacts it needs no build step to exist.
 */

import raw from "../../../config/sky-events.json";

export type CuratedEventKind = "meteor_shower" | "festival" | "comet" | "other";

export interface CuratedLocation {
  latitude: number;
  longitude: number;
  place: string;
}

export interface CuratedEvent {
  id: string;
  name: string;
  kind: CuratedEventKind;
  /**
   * First and last day the event is active, anchored at 12:00 UTC. Midday
   * rather than midnight so that formatting the instant in any plausible
   * timezone still prints the calendar date that was actually curated.
   */
  activeFrom: Date;
  activeTo: Date;
  /** Instant of maximum, UTC. Null for events without one (festivals). */
  peakUtc: Date | null;
  /** Zenithal hourly rate, meteor showers only. */
  zhr: number | null;
  /** J2000 radiant, meteor showers only. */
  radiantRaHours: number | null;
  radiantDecDeg: number | null;
  /** Where it happens, for events tied to a place. */
  location: CuratedLocation | null;
  notes: string;
  sourceUrl: string;
  /** ISO date the row was last checked against its source; null = unverified. */
  verifiedOn: string | null;
}

export interface CuratedLoadResult {
  events: CuratedEvent[];
  /** Rows that failed validation, described well enough to fix the file. */
  problems: string[];
}

const KINDS = new Set<string>(["meteor_shower", "festival", "comet", "other"]);

/**
 * Parse and validate the curated file. A bad row is dropped and reported
 * rather than thrown: one typo in a curated list must not cost the user the
 * computed events, which are the part that always works.
 */
export function parseCuratedEvents(input: unknown): CuratedLoadResult {
  const problems: string[] = [];
  const events: CuratedEvent[] = [];
  const rows = (input as { events?: unknown })?.events;
  if (!Array.isArray(rows)) {
    return { events, problems: ["sky-events.json: missing an `events` array"] };
  }

  const seen = new Set<string>();
  for (const [i, row] of rows.entries()) {
    const where = `sky-events.json row ${i + 1}`;
    const r = row as Record<string, unknown>;
    const id = str(r.id);
    const name = str(r.name);
    const kind = str(r.kind);
    const sourceUrl = str(r.source_url);
    const activeFrom = isoDate(r.active_from);
    const activeTo = isoDate(r.active_to);

    if (!id || !name || !kind || !sourceUrl) {
      problems.push(`${where}: id, name, kind and source_url are all required`);
      continue;
    }
    if (seen.has(id)) {
      problems.push(`${where}: duplicate id "${id}"`);
      continue;
    }
    if (!KINDS.has(kind)) {
      problems.push(`${where} (${id}): unknown kind "${kind}"`);
      continue;
    }
    if (!activeFrom || !activeTo || activeTo < activeFrom) {
      problems.push(`${where} (${id}): active_from/active_to must be ISO dates in order`);
      continue;
    }

    const peakUtc = r.peak_utc == null ? null : new Date(String(r.peak_utc));
    if (peakUtc && Number.isNaN(peakUtc.getTime())) {
      problems.push(`${where} (${id}): peak_utc is not a valid instant`);
      continue;
    }

    const radiantRaHours = num(r.radiant_ra_hours);
    const radiantDecDeg = num(r.radiant_dec_deg);
    if (kind === "meteor_shower" && (radiantRaHours === null || radiantDecDeg === null)) {
      problems.push(`${where} (${id}): a meteor shower needs a radiant`);
      continue;
    }

    events.push({
      id,
      name,
      kind: kind as CuratedEventKind,
      activeFrom,
      activeTo,
      peakUtc,
      zhr: num(r.zhr),
      radiantRaHours,
      radiantDecDeg,
      location: location(r.location),
      notes: str(r.notes) ?? "",
      sourceUrl,
      verifiedOn: isoDate(r.verified_on) ? String(r.verified_on) : null,
    });
    seen.add(id);
  }
  return { events, problems };
}

/** The curated list, parsed once at module load. */
export const CURATED: CuratedLoadResult = parseCuratedEvents(raw);

const HALF_DAY_MS = 43_200_000;

/**
 * The true midnight-to-midnight span an event covers. `activeFrom`/`activeTo`
 * are midday anchors for display; overlap and "which nights may I suggest"
 * questions want the whole calendar days, last day included.
 */
export function activeSpan(event: CuratedEvent): { start: Date; end: Date } {
  return {
    start: new Date(event.activeFrom.getTime() - HALF_DAY_MS),
    end: new Date(event.activeTo.getTime() + HALF_DAY_MS),
  };
}

/** Curated events overlapping [start, end]. */
export function curatedEventsInWindow(
  events: CuratedEvent[],
  start: Date,
  end: Date,
): CuratedEvent[] {
  return events
    .filter((e) => {
      const span = activeSpan(e);
      return span.end >= start && span.start <= end;
    })
    .sort((a, b) => anchorOf(a).getTime() - anchorOf(b).getTime());
}

/** The instant an event is sorted and dated by. */
export function anchorOf(event: CuratedEvent): Date {
  return event.peakUtc ?? event.activeFrom;
}

/** Great-circle distance in kilometres. */
export function distanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const R = 6371;
  const toRad = Math.PI / 180;
  const dLat = (lat2 - lat1) * toRad;
  const dLon = (lon2 - lon1) * toRad;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLon / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.min(1, Math.sqrt(a))));
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
}

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

function isoDate(v: unknown): Date | null {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return null;
  const d = new Date(`${v}T12:00:00Z`);
  return Number.isNaN(d.getTime()) ? null : d;
}

function location(v: unknown): CuratedLocation | null {
  if (!v || typeof v !== "object") return null;
  const r = v as Record<string, unknown>;
  const latitude = num(r.latitude);
  const longitude = num(r.longitude);
  const place = str(r.place);
  if (latitude === null || longitude === null || !place) return null;
  return { latitude, longitude, place };
}
