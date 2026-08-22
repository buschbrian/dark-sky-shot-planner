/**
 * The Answer. Text-first: every number carries its source and age, nothing
 * is presented as more authoritative than it is.
 */

import type { NightReport } from "../astronomy/planner";

export interface AnswerContext {
  report: NightReport;
  lat: number;
  lon: number;
  gcMinAltDeg: number;
  radianceAtPoint: { value: number | null; year: number; label: string };
  landManager: { label: string; agencyUrl: string | null } | null;
  cloudPct: number | null;
  cloudAttribution: string | null;
}

const timeFmt = new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit" });

export function localTime(d: Date): string {
  return timeFmt.format(d);
}

function fmtMinutes(mins: number): string {
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return h > 0 ? `${h} h ${m} min` : `${m} min`;
}

export function renderAnswer(el: HTMLElement, ctx: AnswerContext): void {
  el.replaceChildren();

  const { report, gcMinAltDeg } = ctx;

  if (report.noAstronomicalDarkness || !report.darkness) {
    el.append(
      verdict(
        "No astronomical darkness on this date at this location.",
        "The sun never gets below −18° tonight (high latitude, summer). There is no window to plan around — pick a different date or a location farther south.",
      ),
    );
    return;
  }

  // Headline: moon-free astronomical darkness in minutes.
  const headline = document.createElement("p");
  headline.className = "headline";
  const strong = document.createElement("strong");
  strong.textContent = `${fmtMinutes(report.moonFreeMinutes)} of moon-free darkness`;
  headline.append(strong);
  el.append(headline);

  const rows: [string, string][] = [
    [
      "Astronomical dark",
      `${localTime(report.darkness.start)} – ${localTime(report.darkness.end)} (${fmtMinutes(
        Math.round((report.darkness.end.getTime() - report.darkness.start.getTime()) / 60000),
      )})`,
    ],
    ["Moon illumination", `${Math.round(report.moonIllumFraction * 100)}% at moon-free peak`],
    [
      "Moon events in dark",
      [
        report.moonset ? `moonset ${localTime(report.moonset)}` : null,
        report.moonrise ? `moonrise ${localTime(report.moonrise)}` : null,
      ]
        .filter(Boolean)
        .join(", ") || "none during darkness",
    ],
  ];

  if (!report.gc.risesDuringDarkness) {
    rows.push([
      "Galactic Center",
      `Not above the horizon during darkness tonight — it is out of season here. Try April through September.`,
    ]);
  } else {
    const usable =
      (report.gc.maxAltitudeDeg ?? -90) >= gcMinAltDeg
        ? `usable (threshold ${gcMinAltDeg}°)`
        : `below the ${gcMinAltDeg}° useful-photography threshold`;
    rows.push([
      "Galactic Center",
      `peaks ${report.gc.maxAltitudeDeg}° at ${localTime(report.gc.maxAltitudeAt!)} — ${usable}`,
    ]);
  }

  if (ctx.cloudPct !== null) {
    rows.push(["Cloud cover forecast", `${ctx.cloudPct}% average over the moon-free window`]);
  }

  if (ctx.radianceAtPoint.value !== null) {
    rows.push([
      "Sky brightness",
      `${ctx.radianceAtPoint.label} (VIIRS ${ctx.radianceAtPoint.year} composite — an annual average, not a live reading)`,
    ]);
  }

  if (ctx.landManager) {
    rows.push(["Land manager", `${ctx.landManager.label} — see provenance for the disclaimer`]);
  }

  const dl = document.createElement("dl");
  dl.className = "answer-grid";
  for (const [dtText, ddText] of rows) {
    const dt = document.createElement("dt");
    dt.textContent = dtText;
    const dd = document.createElement("dd");
    dd.textContent = ddText;
    dl.append(dt, dd);
  }
  el.append(dl);

  if (report.moonFreeWindows.length > 1) {
    const note = document.createElement("p");
    note.className = "hint";
    note.textContent = `Split into ${report.moonFreeWindows.length} windows by the moon rising/setting.`;
    el.append(note);
  }
}

export function renderAnswerError(el: HTMLElement, message: string): void {
  el.replaceChildren(verdict(message));
}

function verdict(title: string, detail?: string): HTMLElement {
  const box = document.createElement("div");
  box.className = "verdict";
  const p = document.createElement("p");
  p.className = "headline";
  p.textContent = title;
  box.append(p);
  if (detail) {
    const d = document.createElement("p");
    d.textContent = detail;
    box.append(d);
  }
  return box;
}
