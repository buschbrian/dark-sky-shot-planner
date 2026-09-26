/**
 * The date that names "tonight" in the browser's time zone, matching how
 * `planNight` reads a date (that evening, 21:00 local). Before local noon the
 * night that began yesterday is still the current one, the same rule as
 * `eveningFor` in the shower code.
 */
export function tonightIso(now: Date = new Date()): string {
  const evening = new Date(now);
  if (evening.getHours() < 12) evening.setDate(evening.getDate() - 1);
  const y = evening.getFullYear();
  const m = String(evening.getMonth() + 1).padStart(2, "0");
  const d = String(evening.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}
