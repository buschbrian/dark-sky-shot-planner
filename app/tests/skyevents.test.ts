import { describe, expect, it } from "vitest";

import {
  CURATED,
  activeSpan,
  curatedEventsInWindow,
  distanceKm,
  parseCuratedEvents,
} from "../src/events/curated";
import {
  buildSkyEvents,
  provenanceLabel,
  type Formatters,
} from "../src/events/agenda";
import type { Site } from "../src/astronomy/events";

const MILLCREEK: Site = { latitude: 40.687, longitude: -111.824, elevationM: 1400 };

/**
 * Fixed UTC−6 formatters. The app formats in the reader's zone; the suite
 * must not, or it would pass or fail depending on where CI runs.
 */
const MDT: Formatters = {
  time: (d) => new Date(d.getTime() - 6 * 3_600_000).toISOString().slice(11, 16),
  date: (d) => new Date(d.getTime() - 6 * 3_600_000).toISOString().slice(5, 10),
};

/** Night of 2026-09-22 planned from Millcreek — the golden scenario. */
const CENTRE = new Date("2026-09-22T21:00:00-06:00");

describe("curated sky-events file", () => {
  it("parses with no problems", () => {
    expect(CURATED.problems).toEqual([]);
    expect(CURATED.events.length).toBeGreaterThan(0);
  });

  it("gives every row a source URL", () => {
    for (const e of CURATED.events) {
      expect(e.sourceUrl).toMatch(/^https:\/\//);
    }
  });

  it("gives every meteor shower a radiant and a peak", () => {
    for (const e of CURATED.events.filter((x) => x.kind === "meteor_shower")) {
      expect(e.radiantRaHours).not.toBeNull();
      expect(e.radiantDecDeg).not.toBeNull();
      expect(e.peakUtc).not.toBeNull();
      expect(e.radiantRaHours!).toBeGreaterThanOrEqual(0);
      expect(e.radiantRaHours!).toBeLessThan(24);
      expect(Math.abs(e.radiantDecDeg!)).toBeLessThanOrEqual(90);
    }
  });

  it("gives every festival a location", () => {
    for (const e of CURATED.events.filter((x) => x.kind === "festival")) {
      expect(e.location).not.toBeNull();
    }
  });

  it("marks the rows whose peak date was never verified", () => {
    const unverified = CURATED.events.filter((e) => e.verifiedOn === null).map((e) => e.id);
    expect(unverified).toContain("leonids-2026");
    expect(unverified).toContain("geminids-2026");
    for (const id of unverified) {
      const row = CURATED.events.find((e) => e.id === id)!;
      // An unverified row must say why in its own notes, not only in the label.
      expect(row.notes.toLowerCase()).toContain("approximate");
    }
  });

  it("dates every row so the calendar day survives formatting west of UTC", () => {
    for (const e of CURATED.events) {
      expect(e.activeFrom.getUTCHours()).toBe(12);
      expect(e.activeTo.getUTCHours()).toBe(12);
      expect(e.activeTo >= e.activeFrom).toBe(true);
    }
  });
});

describe("parseCuratedEvents", () => {
  const good = {
    id: "x",
    name: "X",
    kind: "meteor_shower",
    active_from: "2026-01-01",
    active_to: "2026-01-10",
    peak_utc: "2026-01-05T00:00:00Z",
    radiant_ra_hours: 1,
    radiant_dec_deg: 2,
    source_url: "https://example.org/x",
    verified_on: "2026-01-01",
  };

  it("drops a shower with no radiant and says which row", () => {
    const r = parseCuratedEvents({
      events: [{ ...good, radiant_ra_hours: null, radiant_dec_deg: null }],
    });
    expect(r.events).toEqual([]);
    expect(r.problems[0]).toContain("needs a radiant");
  });

  it("drops a row with no source_url", () => {
    const r = parseCuratedEvents({ events: [{ ...good, source_url: "" }] });
    expect(r.events).toEqual([]);
    expect(r.problems[0]).toContain("source_url");
  });

  it("drops a duplicate id and keeps the first", () => {
    const r = parseCuratedEvents({ events: [good, { ...good, name: "Y" }] });
    expect(r.events).toHaveLength(1);
    expect(r.events[0]!.name).toBe("X");
    expect(r.problems[0]).toContain("duplicate id");
  });

  it("drops an unknown kind", () => {
    const r = parseCuratedEvents({ events: [{ ...good, kind: "eclipse" }] });
    expect(r.problems[0]).toContain('unknown kind "eclipse"');
  });

  it("rejects a reversed active range", () => {
    const r = parseCuratedEvents({ events: [{ ...good, active_to: "2025-12-01" }] });
    expect(r.problems[0]).toContain("active_from/active_to");
  });

  it("survives a file with no events array", () => {
    expect(parseCuratedEvents({}).problems).toHaveLength(1);
    expect(parseCuratedEvents(null).problems).toHaveLength(1);
  });

  it("treats a blank verified_on as unverified rather than failing the row", () => {
    const r = parseCuratedEvents({ events: [{ ...good, verified_on: null }] });
    expect(r.problems).toEqual([]);
    expect(r.events[0]!.verifiedOn).toBeNull();
  });
});

describe("activeSpan and window overlap", () => {
  it("covers the whole last day of the range", () => {
    const draconids = CURATED.events.find((e) => e.id === "draconids-2026")!;
    const span = activeSpan(draconids);
    expect(span.start.toISOString()).toBe("2026-10-06T00:00:00.000Z");
    expect(span.end.toISOString()).toBe("2026-10-11T00:00:00.000Z");
  });

  it("excludes an event that ends before the window opens", () => {
    const window = { start: new Date("2026-12-01T00:00:00Z"), end: new Date("2026-12-31T00:00:00Z") };
    const ids = curatedEventsInWindow(CURATED.events, window.start, window.end).map((e) => e.id);
    expect(ids).toContain("geminids-2026");
    expect(ids).not.toContain("orionids-2026");
  });
});

describe("distanceKm", () => {
  it("measures Millcreek to Great Basin National Park", () => {
    const km = distanceKm(MILLCREEK.latitude, MILLCREEK.longitude, 39.006, -114.22);
    expect(km).toBeGreaterThan(250);
    expect(km).toBeLessThan(300);
  });

  it("is zero for the same point", () => {
    expect(distanceKm(40, -111, 40, -111)).toBe(0);
  });
});

describe("buildSkyEvents", () => {
  const result = buildSkyEvents(MILLCREEK, CENTRE, { formatters: MDT });
  const titles = result.items.map((i) => i.title);

  it("spans ±30 days of the selected night", () => {
    expect(result.window.start.toISOString()).toBe("2026-08-24T03:00:00.000Z");
    expect(result.window.end.toISOString()).toBe("2026-10-23T03:00:00.000Z");
  });

  it("is sorted by date", () => {
    const times = result.items.map((i) => i.at.getTime());
    expect([...times].sort((a, b) => a - b)).toEqual(times);
  });

  it("keeps every item either inside the window or already running through it", () => {
    for (const i of result.items) {
      const inside = i.at >= result.window.start && i.at <= result.window.end;
      // A curated event can peak past the window while already being active
      // during it — the Taurids, most of the autumn. Its verdict says so.
      const running = i.provenance.kind === "curated" && i.verdict.includes("Active ");
      expect(inside || running).toBe(true);
    }
  });

  it("dates a still-running shower by its peak and names its active range", () => {
    const taurids = result.items.find((i) => i.title === "Northern Taurids")!;
    expect(taurids.at > result.window.end).toBe(true);
    expect(taurids.verdict).toContain("Active 10-13 – 12-02.");
  });

  it("mixes computed and curated events", () => {
    expect(titles).toContain("New Moon");
    expect(titles).toContain("Saturn at opposition");
    expect(titles).toContain("September equinox");
    expect(titles).toContain("Orionids");
    expect(titles).toContain("Great Basin Astronomy Festival");
  });

  it("does not list a shower whose active range is outside the window", () => {
    expect(titles).not.toContain("Geminids");
    expect(titles).not.toContain("Leonids");
  });

  it("spells out the Moon–Jupiter occultation with local times", () => {
    const jupiter = result.items.find((i) => i.title === "Moon and Jupiter")!;
    expect(jupiter.category).toBe("conjunction");
    expect(jupiter.verdict).toContain("Occultation from here");
    expect(jupiter.verdict).toContain("0.171°");
    expect(jupiter.verdict).toContain("02:49");
    expect(jupiter.verdict).toContain("03:10");
    expect(jupiter.provenance.kind).toBe("computed");
  });

  it("gives the Orionids a moon-aware verdict and a better night", () => {
    const orionids = result.items.find((i) => i.title === "Orionids")!;
    expect(orionids.verdict).toContain("ZHR ~20");
    expect(orionids.verdict).toMatch(/Radiant up \d{2}:\d{2}–\d{2}:\d{2}/);
    expect(orionids.verdict).toMatch(/9\d% moon in the way/);
    expect(orionids.verdict).toContain("A better night");
    expect(orionids.verdict).toContain("Active 10-02 – 11-07.");
  });

  it("reports the distance to a festival", () => {
    const festival = result.items.find((i) => i.title === "Great Basin Astronomy Festival")!;
    expect(festival.verdict).toMatch(/2\d\d km from here/);
    expect(festival.until).not.toBeNull();
  });

  it("collapses zodiacal-light nights into ranges", () => {
    const zodiacal = result.items.filter((i) => i.category === "zodiacal");
    expect(zodiacal.length).toBeGreaterThan(0);
    for (const z of zodiacal) {
      expect(z.title).toBe("Zodiacal light, pre-dawn");
      expect(z.until).not.toBeNull();
      expect(z.verdict).toMatch(/\d+ nights? with no moon in the way/);
    }
  });

  it("labels a radiant that never rises here rather than hiding it", () => {
    const patagonia: Site = { latitude: -40.0, longitude: -71.0 };
    const south = buildSkyEvents(patagonia, CENTRE, { formatters: MDT });
    const draconids = south.items.find((i) => i.title === "Draconids")!;
    expect(draconids.verdict).toContain("Below horizon here");
  });

  it("carries curated provenance through to the label", () => {
    const orionids = result.items.find((i) => i.title === "Orionids")!;
    expect(orionids.provenance).toEqual({
      kind: "curated",
      sourceUrl: "https://earthsky.org/astronomy-essentials/earthskys-meteor-shower-guide/",
      verifiedOn: "2026-09-06",
    });
    expect(provenanceLabel(orionids.provenance)).toBe("curated, verified 2026-09-06");
  });

  it("labels computed items as computed, not as a stale data feed", () => {
    expect(provenanceLabel({ kind: "computed" })).toBe("computed");
    expect(provenanceLabel({ kind: "curated", sourceUrl: "x", verifiedOn: null })).toBe(
      "curated — unverified",
    );
  });

  it("surfaces curated-file problems instead of silently shortening the list", () => {
    const broken = parseCuratedEvents({ events: [{ id: "bad" }] });
    const r = buildSkyEvents(MILLCREEK, CENTRE, { formatters: MDT, curated: broken });
    expect(r.problems).toHaveLength(1);
    expect(r.items.every((i) => i.provenance.kind === "computed")).toBe(true);
  });
});
