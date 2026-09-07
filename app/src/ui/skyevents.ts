/**
 * The "Sky events" list under the answer. Same discipline as the answer
 * itself: plain text, one line per event, every line saying where it came
 * from — "computed" for ephemeris, `verified <date>` plus a source link for a
 * curated row (ADR-0006, ADR-0008).
 *
 * A definition list, not a table: it reads correctly linearised on a phone and
 * announces sensibly to a screen reader, and every link is in the normal tab
 * order, so the section is fully usable without the map ever getting focus.
 */

import { provenanceLabel, type SkyEventItem, type SkyEventsResult } from "../events/agenda";

const dayFmt = new Intl.DateTimeFormat([], { month: "short", day: "numeric" });
const dayTimeFmt = new Intl.DateTimeFormat([], {
  month: "short",
  day: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

const CATEGORY_LABEL: Record<SkyEventItem["category"], string> = {
  moon: "Moon",
  planet: "Planet",
  conjunction: "Pairing",
  meteor_shower: "Meteor shower",
  zodiacal: "Zodiacal light",
  season: "Season",
  place: "Event",
};

/** Events spanning nights are dated, not timed: a range has no useful clock. */
function whenText(item: SkyEventItem): string {
  if (item.until) return `${dayFmt.format(item.at)} – ${dayFmt.format(item.until)}`;
  return dayTimeFmt.format(item.at);
}

export function renderSkyEvents(el: HTMLElement, result: SkyEventsResult): void {
  el.replaceChildren();

  const intro = document.createElement("p");
  intro.className = "hint";
  intro.textContent =
    `What else is in the sky within 30 days of this date, from this spot, plus anything ` +
    `already running — ${result.items.length} event${result.items.length === 1 ? "" : "s"}.`;
  el.append(intro);

  if (result.items.length === 0) {
    const empty = document.createElement("p");
    empty.className = "placeholder";
    empty.textContent = "Nothing in the window for this location.";
    el.append(empty);
  } else {
    const list = document.createElement("ul");
    list.className = "event-list";
    for (const item of result.items) list.append(eventRow(item));
    el.append(list);
  }

  // A malformed curated row is a maintainer's bug; say so rather than quietly
  // shipping a shorter list.
  if (result.problems.length > 0) {
    const warn = document.createElement("p");
    warn.className = "hint";
    warn.textContent = `${result.problems.length} curated event row${
      result.problems.length === 1 ? "" : "s"
    } could not be read and are not listed: ${result.problems.join("; ")}`;
    el.append(warn);
  }
}

function eventRow(item: SkyEventItem): HTMLElement {
  const li = document.createElement("li");

  const head = document.createElement("p");
  head.className = "event-head";
  const when = document.createElement("span");
  when.className = "event-when";
  when.textContent = whenText(item);
  const name = document.createElement("strong");
  name.textContent = item.title;
  const kind = document.createElement("span");
  kind.className = "event-kind";
  kind.textContent = CATEGORY_LABEL[item.category];
  head.append(when, document.createTextNode(" "), name, document.createTextNode(" "), kind);

  const verdict = document.createElement("p");
  verdict.className = "event-verdict";
  verdict.textContent = item.verdict;

  const source = document.createElement("p");
  source.className = "event-source hint";
  source.append(document.createTextNode(provenanceLabel(item.provenance)));
  if (item.provenance.kind === "curated") {
    source.append(document.createTextNode(" — "));
    const a = document.createElement("a");
    a.href = item.provenance.sourceUrl;
    a.rel = "noreferrer";
    a.textContent = `source for ${item.title}`;
    source.append(a);
  }

  li.append(head, verdict, source);
  return li;
}

export function renderSkyEventsMessage(el: HTMLElement, message: string): void {
  const p = document.createElement("p");
  p.className = "placeholder";
  p.textContent = message;
  el.replaceChildren(p);
}
