import { darknessWindow } from "../astronomy/planner";

export interface Site {
  latitude: number;
  longitude: number;
}

/**
 * The date that names "tonight" in the browser's time zone, matching how
 * `planNight` reads a date (that evening, 21:00 local).
 *
 * With a site (review B-2): the previous evening's night only while it is
 * still dark there, before its astronomical dawn (civil dawn when the sun
 * never reaches -18°); otherwise the night that starts this evening. Where it
 * never gets darker than civil twilight, this evening. Mirrors
 * `NightDate.current(at:observer:timeZone:)` in SkyCore;
 * `shared/golden/tonight.json` holds the cases both must agree on.
 *
 * Without a site there is no dawn to go by, so the calendar rule stands in:
 * before local noon, the night that began yesterday (`eveningFor` in the
 * shower code).
 */
export function tonightIso(now: Date = new Date(), site?: Site | null): string {
  const today = localIso(now);
  if (!site) {
    return now.getHours() < 12 ? addDays(today, -1) : today;
  }
  return now.getTime() < becomesCurrent(today, site).getTime() ? addDays(today, -1) : today;
}

/** When the night of `isoDate` becomes "tonight": the previous night's dawn, never before local midnight. */
export function becomesCurrent(isoDate: string, site: Site): Date {
  const midnight = new Date(`${isoDate}T00:00:00`);
  const end = darknessEnd(addDays(isoDate, -1), site);
  return end && end.getTime() > midnight.getTime() ? end : midnight;
}

/**
 * When the night of `isoDate` stops being dark: astronomical dawn, or civil
 * dawn when the sun never reaches -18°; null when it never gets darker than
 * civil twilight (or the search lands outside the night).
 */
export function darknessEnd(isoDate: string, site: Site): Date | null {
  const evening = new Date(`${isoDate}T21:00:00`);
  const latest = evening.getTime() + 15 * 3600_000;
  for (const altitude of [-18, -6]) {
    const { window } = darknessWindow(site.latitude, site.longitude, evening, altitude);
    if (window) return window.end.getTime() <= latest ? window.end : null;
  }
  return null;
}

function localIso(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function addDays(isoDate: string, days: number): string {
  const d = new Date(`${isoDate}T12:00:00`);
  d.setDate(d.getDate() + days);
  return localIso(d);
}
