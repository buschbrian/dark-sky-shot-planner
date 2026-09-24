/**
 * "What else is happening in the sky around this date, from this spot?"
 *
 * Assembles the computed events (`astronomy/events.ts`) and the curated ones
 * (`curated.ts`, evaluated at the observer by `astronomy/showers.ts`) into one
 * date-sorted list of plain-language lines, each carrying where it came from:
 * "computed" for ephemeris, a `verified_on` date for a curated row. ADR-0006
 * says every displayed number shows its source and its age; a computed number
 * has no age, and saying so is the honest label. ADR-0008 covers the split.
 */

import {
  DEFAULT_WINDOW_DAYS,
  OCCULTATION_FLAG_DEG,
  PAIRING_MAX_SUN_ALTITUDE_DEG,
  greatestElongations,
  moonPhases,
  moonPlanetPairings,
  planetOppositions,
  seasonMarkers,
  windowAround,
  zodiacalLightRanges,
  type MoonPairing,
  type Site,
  type TimeWindow,
} from "../astronomy/events";
import {
  RADIANT_MIN_ALTITUDE_DEG,
  assessShower,
  type ShowerAssessment,
  type ShowerNight,
} from "../astronomy/showers";
import {
  CURATED,
  activeSpan,
  anchorOf,
  curatedEventsInWindow,
  distanceKm,
  type CuratedEvent,
  type CuratedLoadResult,
} from "./curated";

export type SkyEventCategory =
  | "moon"
  | "planet"
  | "conjunction"
  | "meteor_shower"
  | "zodiacal"
  | "season"
  | "place";

export type SkyEventProvenance =
  | { kind: "computed" }
  | { kind: "curated"; sourceUrl: string; verifiedOn: string | null };

export interface SkyEventItem {
  at: Date;
  /** End instant for events that span nights; null for point events. */
  until: Date | null;
  category: SkyEventCategory;
  title: string;
  /** One plain-language line: what it means from here, on this night. */
  verdict: string;
  provenance: SkyEventProvenance;
}

export interface SkyEventsResult {
  window: TimeWindow;
  items: SkyEventItem[];
  /** Problems in the curated file, surfaced rather than swallowed. */
  problems: string[];
}

export interface Formatters {
  time(d: Date): string;
  date(d: Date): string;
}

const DEFAULT_FORMATTERS: Formatters = {
  time: (d) => new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit" }).format(d),
  date: (d) => new Intl.DateTimeFormat([], { month: "short", day: "numeric" }).format(d),
};

export interface BuildOptions {
  windowDays?: number;
  formatters?: Formatters;
  curated?: CuratedLoadResult;
}

export function buildSkyEvents(
  site: Site,
  centre: Date,
  options: BuildOptions = {},
): SkyEventsResult {
  const fmt = options.formatters ?? DEFAULT_FORMATTERS;
  const curated = options.curated ?? CURATED;
  const window = windowAround(centre, options.windowDays ?? DEFAULT_WINDOW_DAYS);

  const items: SkyEventItem[] = [
    ...moonPhaseItems(window),
    ...planetItems(window),
    ...pairingItems(site, window, fmt),
    ...zodiacalItems(site, window, fmt),
    ...seasonItems(window),
    ...curatedItems(site, window, curated.events, fmt),
  ];

  items.sort((a, b) => a.at.getTime() - b.at.getTime());
  return { window, items, problems: curated.problems };
}

// ------------------------------------------------------------------ computed

const MOON_PHASE_VERDICT: Record<number, string> = {
  0: "The darkest nights of the month — no moon in the sky at any hour.",
  90: "Moon sets near local midnight; the second half of the night is moon-free.",
  180: "Up all night. There is no moon-free darkness on either side of this date.",
  270: "Moon rises near local midnight; the first half of the night is moon-free.",
};

function moonPhaseItems(window: TimeWindow): SkyEventItem[] {
  return moonPhases(window).map((p) => ({
    at: p.at,
    until: null,
    category: "moon" as const,
    title: p.name,
    verdict: MOON_PHASE_VERDICT[p.angle] ?? "",
    provenance: { kind: "computed" as const },
  }));
}

function planetItems(window: TimeWindow): SkyEventItem[] {
  const oppositions = planetOppositions(window).map((e) => ({
    at: e.at,
    until: null,
    category: "planet" as const,
    title: `${e.body} at opposition`,
    verdict: `Opposite the Sun: closest, brightest, and above the horizon all night.`,
    provenance: { kind: "computed" as const },
  }));
  const elongations = greatestElongations(window).map((e) => ({
    at: e.at,
    until: null,
    category: "planet" as const,
    title: `${e.body} at greatest ${e.visibility} elongation`,
    verdict:
      `${e.elongationDeg}° from the Sun — the widest separation of this apparition, ` +
      (e.visibility === "evening" ? "low in the west after sunset." : "low in the east before sunrise."),
    provenance: { kind: "computed" as const },
  }));
  return [...oppositions, ...elongations];
}

function pairingItems(site: Site, window: TimeWindow, fmt: Formatters): SkyEventItem[] {
  return moonPlanetPairings(site, window).map((p) => ({
    at: p.at,
    until: null,
    category: "conjunction" as const,
    title: `Moon and ${p.body}`,
    verdict: pairingVerdict(p, fmt),
    provenance: { kind: "computed" as const },
  }));
}

/**
 * Every separation printed here is topocentric — what is seen from this spot
 * at the instant printed next to it (ADR-0008 §4). The geocentric minimum only
 * decides whether an occultation is worth checking.
 */
export function pairingVerdict(p: MoonPairing, fmt: Formatters): string {
  const moonPct = Math.round(p.moonIllumFraction * 100);
  const parts: string[] = [];
  if (p.observableHere) {
    parts.push(
      `${p.separationDeg.toFixed(1)}° apart at ${fmt.time(p.at)}, ` +
        `${Math.round(p.moonAltitudeDeg)}° and ${Math.round(p.bodyAltitudeDeg)}° up, Moon ${moonPct}% lit.`,
    );
  } else {
    parts.push(
      `Closest approach from here ${p.separationDeg.toFixed(1)}° at ${fmt.time(p.at)}, ` +
        `but not above 5° in dark sky.`,
    );
  }

  const occ = p.occultation;
  if (!p.possibleOccultation || !occ) return parts.join(" ");

  if (!occ.behindDiscFromHere) {
    // Only worth saying when the planet really is occulted for someone.
    if (p.geocentricMinDeg < OCCULTATION_FLAG_DEG) {
      const clearance = Math.max(0, occ.minSeparationDeg - occ.moonRadiusDeg);
      parts.push(
        `An occultation somewhere on Earth, but not here: from this spot it misses the disc by ` +
          `${clearance.toFixed(2)}° at ${fmt.time(occ.minSeparationAt)}.`,
      );
    }
    return parts.join(" ");
  }

  parts.push(
    `Occultation from here — ${p.body} passes behind the Moon, closest ` +
      `${occ.minSeparationDeg.toFixed(3)}° at ${fmt.time(occ.minSeparationAt)}.`,
  );
  if (occ.moonAltitudeDeg < 0 && occ.reappearsAt && (occ.reappearMoonAltitudeDeg ?? -1) >= 0) {
    parts.push(
      `The Moon is still below the horizon at the minimum; it reappears at ` +
        `${fmt.time(occ.reappearsAt)} with the Moon only ${occ.reappearMoonAltitudeDeg}° up — ` +
        `you need a flat eastern horizon.`,
    );
  } else if (occ.moonAltitudeDeg < 0) {
    parts.push("The whole event happens below the horizon here.");
  } else {
    if (occ.sunAltitudeDeg > PAIRING_MAX_SUN_ALTITUDE_DEG) {
      parts.push(`In daylight here (Sun ${Math.round(occ.sunAltitudeDeg)}° up) — a telescope job.`);
    }
    if (occ.reappearsAt) parts.push(`Reappears at ${fmt.time(occ.reappearsAt)}.`);
  }
  return parts.join(" ");
}

function zodiacalItems(site: Site, window: TimeWindow, fmt: Formatters): SkyEventItem[] {
  return zodiacalLightRanges(site, window).map((r) => ({
    at: r.start,
    until: r.end,
    category: "zodiacal" as const,
    title:
      r.season === "autumn_morning" ? "Zodiacal light, pre-dawn" : "Zodiacal light, after dusk",
    verdict:
      `${r.nights} night${r.nights === 1 ? "" : "s"} with no moon in the way, ` +
      `${fmt.date(r.start)} – ${fmt.date(r.end)}. Look ` +
      (r.season === "autumn_morning"
        ? `east about an hour before astronomical dawn (${fmt.time(r.start)} on the first night).`
        : `west about an hour after astronomical dusk (${fmt.time(r.start)} on the first night).`),
    provenance: { kind: "computed" as const },
  }));
}

function seasonItems(window: TimeWindow): SkyEventItem[] {
  return seasonMarkers(window).map((s) => ({
    at: s.at,
    until: null,
    category: "season" as const,
    title: s.name,
    verdict: "Night length turns here — the darkness window changes fastest around this date.",
    provenance: { kind: "computed" as const },
  }));
}

// ------------------------------------------------------------------- curated

function curatedItems(
  site: Site,
  window: TimeWindow,
  events: CuratedEvent[],
  fmt: Formatters,
): SkyEventItem[] {
  return curatedEventsInWindow(events, window.start, window.end).map((e) => {
    const provenance = {
      kind: "curated" as const,
      sourceUrl: e.sourceUrl,
      verifiedOn: e.verifiedOn,
    };
    if (e.kind === "meteor_shower" && e.radiantRaHours !== null && e.radiantDecDeg !== null) {
      const span = activeSpan(e);
      const assessment = assessShower(
        site,
        { raHours: e.radiantRaHours, decDeg: e.radiantDecDeg },
        e.peakUtc ?? anchorOf(e),
        span.start,
        span.end,
      );
      // Dated by its peak, not its span: the peak night is the decision, and
      // the active range is one clause of the verdict.
      return {
        at: anchorOf(e),
        until: null,
        category: "meteor_shower" as const,
        title: e.name,
        verdict: showerVerdict(e, assessment, fmt),
        provenance,
      };
    }
    return {
      at: anchorOf(e),
      until: e.activeTo,
      category: "place" as const,
      title: e.name,
      verdict: placeVerdict(site, e, fmt),
      provenance,
    };
  });
}

/**
 * Plain language for one shower at this spot: where the radiant gets to, when
 * the Moon is in the way, and what is actually left to shoot.
 */
export function showerVerdict(
  event: CuratedEvent,
  assessment: ShowerAssessment,
  fmt: Formatters,
): string {
  const active = `Active ${fmt.date(event.activeFrom)} – ${fmt.date(event.activeTo)}.`;
  const zhr = event.zhr === null ? "" : `ZHR ~${event.zhr}. `;
  if (!assessment.observableHere) {
    return [
      `${zhr}Below horizon here — the radiant never clears ${RADIANT_MIN_ALTITUDE_DEG}° during astronomical darkness.`,
      active,
      event.notes,
    ]
      .filter(Boolean)
      .join(" ");
  }

  const night = assessment.peakNight;
  const parts = [zhr + nightVerdict(night, fmt), active];
  if (assessment.betterNight) {
    parts.push(
      `A better night inside the active range: ${fmt.date(assessment.betterNight.eveningUtc)}, ` +
        `${assessment.betterNight.usableMinutes} min moonless with the radiant up.`,
    );
  }
  if (event.notes) parts.push(event.notes);
  return parts.join(" ");
}

function nightVerdict(night: ShowerNight, fmt: Formatters): string {
  if (!night.radiantWindow) {
    return `Radiant below ${RADIANT_MIN_ALTITUDE_DEG}° all night on the peak night; try the neighbouring dates.`;
  }
  const w = night.radiantWindow;
  const highest =
    `Radiant up ${fmt.time(w.start)}–${fmt.time(w.end)}` +
    (night.maxAltitudeAt ? `, highest ${night.maxAltitudeDeg}° at ${fmt.time(night.maxAltitudeAt)}` : "");
  const moonPct = Math.round(night.moonIllumFraction * 100);

  if (night.usableMinutes === 0) {
    return `${highest}, but a ${moonPct}% moon is up throughout — nothing usable.`;
  }
  const fullyMoonless =
    night.usableWindows.length === 1 &&
    night.usableWindows[0]!.start.getTime() <= w.start.getTime() + 60_000 &&
    night.usableWindows[0]!.end.getTime() >= w.end.getTime() - 60_000;
  if (fullyMoonless) {
    return `${highest}, moonless.`;
  }
  const usable = night.usableWindows
    .map((u) => `${fmt.time(u.start)}–${fmt.time(u.end)}`)
    .join(", ");
  return `${highest}. ${moonPct}% moon in the way for part of it — usable ${usable}.`;
}

function placeVerdict(site: Site, event: CuratedEvent, _fmt: Formatters): string {
  if (!event.location) return event.notes;
  const km = distanceKm(
    site.latitude,
    site.longitude,
    event.location.latitude,
    event.location.longitude,
  );
  return `${event.location.place} — ${km} km from here. ${event.notes}`.trim();
}

/** Freshness label for an item, in the ADR-0006 spirit. */
export function provenanceLabel(p: SkyEventProvenance): string {
  if (p.kind === "computed") return "computed";
  if (!p.verifiedOn) return "curated — unverified";
  return `curated, verified ${p.verifiedOn}`;
}
