/**
 * Terrain skyline around an observer (format: `config/horizon-profiles/README.md`).
 * SkyCore's `HorizonProfile.swift` parses and interpolates identically.
 */

export const HORIZON_CSV_HEADER = "azimuth_deg,horizon_alt_deg";

export interface HorizonSample {
  azimuthDeg: number;
  altitudeDeg: number;
}

export class HorizonProfile {
  /** Strictly increasing azimuth in [0, 360). */
  readonly samples: readonly HorizonSample[];

  constructor(samples: HorizonSample[]) {
    if (samples.length === 0) throw new Error("horizon profile: no samples");
    samples.forEach((s, i) => {
      if (!Number.isFinite(s.azimuthDeg) || s.azimuthDeg < 0 || s.azimuthDeg >= 360) {
        throw new Error(`horizon profile line ${i + 2}: azimuth ${s.azimuthDeg} outside [0, 360)`);
      }
      if (!Number.isFinite(s.altitudeDeg) || s.altitudeDeg < -90 || s.altitudeDeg > 90) {
        throw new Error(`horizon profile line ${i + 2}: altitude ${s.altitudeDeg} outside [-90, 90]`);
      }
      if (i > 0 && s.azimuthDeg <= samples[i - 1]!.azimuthDeg) {
        throw new Error(`horizon profile line ${i + 2}: azimuths must increase`);
      }
    });
    this.samples = samples;
  }

  static flat(altitudeDeg = 0): HorizonProfile {
    return new HorizonProfile([{ azimuthDeg: 0, altitudeDeg }]);
  }

  static parse(csv: string): HorizonProfile {
    const lines = csv.split(/\r?\n/).map((l) => l.trim());
    if (lines[0] !== HORIZON_CSV_HEADER) {
      throw new Error(`horizon profile: expected header "${HORIZON_CSV_HEADER}", got "${lines[0] ?? ""}"`);
    }
    const samples: HorizonSample[] = [];
    lines.slice(1).forEach((line, i) => {
      if (line === "") return;
      const fields = line.split(",").map((f) => f.trim());
      const az = fields.length === 2 && fields[0] !== "" ? Number(fields[0]) : NaN;
      const alt = fields.length === 2 && fields[1] !== "" ? Number(fields[1]) : NaN;
      if (Number.isNaN(az) || Number.isNaN(alt)) {
        throw new Error(`horizon profile line ${i + 2}: cannot parse "${line}"`);
      }
      samples.push({ azimuthDeg: az, altitudeDeg: alt });
    });
    return new HorizonProfile(samples);
  }

  /** Terrain altitude at `azimuthDeg`, linear between samples, wrapping across north. */
  altitudeAt(azimuthDeg: number): number {
    const s = this.samples;
    const n = s.length;
    if (n === 1) return s[0]!.altitudeDeg;
    const a = ((azimuthDeg % 360) + 360) % 360;
    // Largest i with s[i].azimuthDeg <= a, or the last sample (the wrap segment).
    let lo = 0;
    let hi = n - 1;
    let i = n - 1;
    while (lo <= hi) {
      const mid = Math.floor((lo + hi) / 2);
      if (s[mid]!.azimuthDeg <= a) {
        i = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    const j = (i + 1) % n;
    const a0 = s[i]!.azimuthDeg;
    const span = (s[j]!.azimuthDeg - a0 + 360) % 360;
    const offset = (a - a0 + 360) % 360;
    return s[i]!.altitudeDeg + ((s[j]!.altitudeDeg - s[i]!.altitudeDeg) * offset) / span;
  }
}
