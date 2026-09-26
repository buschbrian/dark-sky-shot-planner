// Reference apparent positions for SkyCore's StarField tests, from the web
// app's astronomy-engine (npm, same version as the vendored C port).
//
//   NODE_PATH=<repo>/node_modules node ios/scripts/star-reference.cjs
//
// Inputs are SIMBAD's J2000 (ICRS) positions and Hipparcos (van Leeuwen 2007)
// proper motions, read 2026-09-26 from https://simbad.cds.unistra.fr/:
// a published source independent of the bundled BSC5 file. Proper motion is
// applied linearly to the date, then DefineStar + Equator(of date, with
// aberration) + Horizon(normal refraction). Paste the output into
// StarFieldTests.swift.
const A = require("astronomy-engine");

const stars = [
  // name, RA deg, Dec deg, pmRA* mas/yr, pmDec mas/yr, distance ly
  ["Sirius", 101.28715533, -16.71611586, -546.01, -1223.07, 8.6],
  ["Vega", 279.23473479, 38.78368896, 200.94, 286.23, 25.0],
  ["Polaris", 37.95456067, 89.26410897, 44.48, -11.85, 433],
];
const sites = [
  ["Candlestick Camp", 38.374031, -109.965416],
];
const times = ["2026-07-15T05:00:00Z", "2026-12-15T12:00:00Z"];

for (const [site, lat, lon] of sites) {
  const observer = new A.Observer(lat, lon, 0);
  for (const iso of times) {
    const date = new Date(iso);
    const years = (date.getTime() - Date.UTC(2000, 0, 1, 12)) / (365.25 * 86400000);
    for (const [name, ra, dec, pmra, pmdec, ly] of stars) {
      const d = dec + (pmdec * years) / 3.6e6;
      const r = ra + (pmra * years) / 3.6e6 / Math.cos((dec * Math.PI) / 180);
      A.DefineStar(A.Body.Star1, r / 15, d, ly);
      const eq = A.Equator(A.Body.Star1, date, observer, true, true);
      const hor = A.Horizon(date, observer, eq.ra, eq.dec, "normal");
      console.log(
        `(${JSON.stringify(name)}, ${JSON.stringify(iso)}, raOfDateHours: ${eq.ra.toFixed(6)}, decOfDate: ${eq.dec.toFixed(5)}, ` +
          `alt: ${hor.altitude.toFixed(4)}, az: ${hor.azimuth.toFixed(4)}),`,
      );
    }
  }
}

// The celestial pole of date and Polaris's distance from it.
for (const iso of times) {
  const date = new Date(iso);
  const rot = A.Rotation_EQJ_EQD(date);
  // The pole of date expressed in J2000 is the third row of EQJ->EQD.
  const pole = A.SphereFromVector(new A.Vector(rot.rot[0][2], rot.rot[1][2], rot.rot[2][2], date));
  const years = (date.getTime() - Date.UTC(2000, 0, 1, 12)) / (365.25 * 86400000);
  const p = stars[2];
  const pd = p[2] + (p[4] * years) / 3.6e6;
  const pr = p[1] + (p[3] * years) / 3.6e6 / Math.cos((p[2] * Math.PI) / 180);
  const v1 = A.VectorFromSphere(new A.Spherical(pd, pr, 1), date);
  const v2 = A.VectorFromSphere(new A.Spherical(pole.lat, pole.lon, 1), date);
  const sep = A.AngleBetween(v1, v2);
  console.log(`// ${iso}: Polaris is ${sep.toFixed(4)} deg from the mean-of-date pole (J2000 pole direction ${pole.lon.toFixed(4)}, ${pole.lat.toFixed(4)})`);
}
