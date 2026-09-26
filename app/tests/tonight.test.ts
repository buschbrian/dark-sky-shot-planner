import { describe, expect, it } from "vitest";

import { tonightIso } from "../src/state/tonight";

// A Mountain West browser: after 18:00 MDT the UTC date is already tomorrow.
process.env.TZ = "America/Denver";

describe("tonightIso", () => {
  it("runs in the zone the regression needs", () => {
    expect(new Date("2026-09-26T12:00:00Z").getTimezoneOffset()).toBe(360);
  });

  it("keeps the local date in the evening, when the UTC date has rolled over", () => {
    const evening = new Date("2026-09-27T02:30:00Z"); // 20:30 MDT on the 26th
    expect(evening.toISOString().slice(0, 10)).toBe("2026-09-27");
    expect(tonightIso(evening)).toBe("2026-09-26");
  });

  it("before local noon, names the night that began yesterday", () => {
    expect(tonightIso(new Date("2026-09-27T08:00:00Z"))).toBe("2026-09-26"); // 02:00 MDT
    expect(tonightIso(new Date("2026-09-27T17:59:00Z"))).toBe("2026-09-26"); // 11:59 MDT
  });

  it("from local noon, names tonight", () => {
    expect(tonightIso(new Date("2026-09-27T18:00:00Z"))).toBe("2026-09-27"); // 12:00 MDT
  });

  it("crosses month and year boundaries", () => {
    expect(tonightIso(new Date("2026-10-01T09:00:00Z"))).toBe("2026-09-30"); // 03:00 MDT Oct 1
    expect(tonightIso(new Date("2027-01-01T10:00:00Z"))).toBe("2026-12-31"); // 03:00 MST Jan 1
  });
});
