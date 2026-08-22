/**
 * Keyless, proxy-free cloud/sky-cover forecast for one point, fetched
 * client-side on demand from Open-Meteo. No key; no server involvement.
 */

export interface HourlyCloud {
  timeUtc: string;
  /** Total sky cover, percent 0-100. */
  cloudCover: number;
}

export interface CloudForecast {
  hourly: HourlyCloud[];
  /** Human-readable model attribution shown next to the numbers. */
  attribution: string;
}

export async function fetchCloudForecast(
  lat: number,
  lon: number,
): Promise<CloudForecast> {
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
    "&hourly=cloud_cover&cloud_cover_unit=percentage&forecast_days=3&timezone=UTC";
  const res = await fetch(url);
  if (!res.ok) throw new Error(`open-meteo ${res.status}`);
  const body = (await res.json()) as {
    hourly?: { time?: string[]; cloud_cover?: number[] };
  };
  const times = body.hourly?.time ?? [];
  const cover = body.hourly?.cloud_cover ?? [];
  const hourly: HourlyCloud[] = times.map((t, i) => ({
    timeUtc: t,
    cloudCover: cover[i] ?? 0,
  }));
  return { hourly, attribution: "Open-Meteo (ECMWF/GFS blend), fetched just now" };
}

/** Average cloud cover during a UTC interval, null when data is out of range. */
export function averageCloudCover(
  forecast: CloudForecast,
  startUtc: Date,
  endUtc: Date,
): number | null {
  const inRange = forecast.hourly.filter((h) => {
    const t = new Date(`${h.timeUtc}Z`).getTime();
    return t >= startUtc.getTime() && t <= endUtc.getTime();
  });
  if (!inRange.length) return null;
  return Math.round(inRange.reduce((a, h) => a + h.cloudCover, 0) / inRange.length);
}
