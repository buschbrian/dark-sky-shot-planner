#!/usr/bin/env python3
"""Build SkyCore's bundled star and constellation files from their sources.

Deterministic and offline once the inputs are downloaded; standard library
only. Sources, licenses and checksums: docs/data-licensing.md ("Sky view
catalogs"). Download the inputs first:

  curl -fO https://heasarc.gsfc.nasa.gov/FTP/heasarc/dbase/tdat_files/heasarc_bsc5p.tdat.gz
  gunzip heasarc_bsc5p.tdat.gz
  D3=https://raw.githubusercontent.com/ofrohn/d3-celestial/7e720a3de062059d4c5400a379146a601d9010e0/data
  curl -fO $D3/constellations.lines.json
  curl -fO $D3/constellations.json

then run

  python3 ios/scripts/build-sky-catalogs.py <input dir>

It writes ios/Packages/SkyCore/Sources/SkyCore/Resources/sky/.
"""

from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "Packages/SkyCore/Sources/SkyCore/Resources/sky"
MAG_LIMIT = 6.5
# A figure vertex must sit this close to a catalogue star (degrees). The
# d3-celestial vertices are Hipparcos-based J2000 positions; BSC5 agrees to
# about an arcsecond, so anything wider than a few arcminutes is a mismatch.
MATCH_TOLERANCE_DEG = 0.05

# IAU WGSN approved names (https://www.iau.org/public/themes/naming_stars/),
# keyed by the BSC5 Bayer designation so no HR number is typed by hand.
# Names are facts; this short list is compiled for labels only.
STAR_NAMES = [
    ("Sirius", "Alp CMa"), ("Canopus", "Alp Car"), ("Arcturus", "Alp Boo"),
    ("Rigil Kentaurus", "Alp1Cen"), ("Vega", "Alp Lyr"), ("Capella", "Alp Aur"),
    ("Rigel", "Bet Ori"), ("Procyon", "Alp CMi"), ("Achernar", "Alp Eri"),
    ("Betelgeuse", "Alp Ori"), ("Hadar", "Bet Cen"), ("Altair", "Alp Aql"),
    ("Acrux", "Alp1Cru"), ("Aldebaran", "Alp Tau"), ("Antares", "Alp Sco"),
    ("Spica", "Alp Vir"), ("Pollux", "Bet Gem"), ("Fomalhaut", "Alp PsA"),
    ("Deneb", "Alp Cyg"), ("Mimosa", "Bet Cru"), ("Regulus", "Alp Leo"),
    ("Adhara", "Eps CMa"), ("Castor", "Alp Gem"), ("Shaula", "Lam Sco"),
    ("Bellatrix", "Gam Ori"), ("Elnath", "Bet Tau"), ("Alnilam", "Eps Ori"),
    ("Alnitak", "Zet Ori"), ("Mintaka", "Del Ori"), ("Saiph", "Kap Ori"),
    ("Alioth", "Eps UMa"), ("Dubhe", "Alp UMa"), ("Merak", "Bet UMa"),
    ("Phecda", "Gam UMa"), ("Megrez", "Del UMa"), ("Mizar", "Zet UMa"),
    ("Alkaid", "Eta UMa"), ("Mirfak", "Alp Per"), ("Algol", "Bet Per"),
    ("Wezen", "Del CMa"), ("Kaus Australis", "Eps Sgr"), ("Nunki", "Sig Sgr"),
    ("Sargas", "The Sco"), ("Menkalinan", "Bet Aur"), ("Alhena", "Gam Gem"),
    ("Polaris", "Alp UMi"), ("Kochab", "Bet UMi"), ("Alphard", "Alp Hya"),
    ("Hamal", "Alp Ari"), ("Diphda", "Bet Cet"), ("Alpheratz", "Alp And"),
    ("Mirach", "Bet And"), ("Almach", "Gam1And"), ("Rasalhague", "Alp Oph"),
    ("Denebola", "Bet Leo"), ("Albireo", "Bet1Cyg"), ("Sadr", "Gam Cyg"),
    ("Enif", "Eps Peg"), ("Scheat", "Bet Peg"), ("Markab", "Alp Peg"),
    ("Algenib", "Gam Peg"), ("Eltanin", "Gam Dra"), ("Alderamin", "Alp Cep"),
    ("Schedar", "Alp Cas"), ("Caph", "Bet Cas"), ("Alcyone", "Eta Tau"),
    ("Alphecca", "Alp CrB"), ("Izar", "Eps Boo"), ("Tarazed", "Gam Aql"),
    ("Zubeneschamali", "Bet Lib"), ("Zubenelgenubi", "Alp2Lib"),
    ("Unukalhai", "Alp Ser"), ("Vindemiatrix", "Eps Vir"), ("Menkar", "Alp Cet"),
    ("Kaus Media", "Del Sgr"), ("Ascella", "Zet Sgr"), ("Dschubba", "Del Sco"),
    ("Kornephoros", "Bet Her"), ("Rasalgethi", "Alp1Her"), ("Sheliak", "Bet Lyr"),
    ("Sulafat", "Gam Lyr"), ("Deneb Algedi", "Del Cap"), ("Sadalsuud", "Bet Aqr"),
    ("Sadalmelik", "Alp Aqr"), ("Naos", "Zet Pup"), ("Suhail", "Lam Vel"),
    ("Mirzam", "Bet CMa"), ("Arneb", "Alp Lep"), ("Phact", "Alp Col"),
    ("Cor Caroli", "Alp2CVn"), ("Muphrid", "Eta Boo"), ("Nekkar", "Bet Boo"),
    ("Thuban", "Alp Dra"), ("Rastaban", "Bet Dra"), ("Alnair", "Alp Gru"),
    ("Peacock", "Alp Pav"), ("Atria", "Alp TrA"), ("Gacrux", "Gam Cru"),
    ("Menkent", "The Cen"), ("Alsephina", "Del Vel"), ("Avior", "Eps Car"),
    ("Miaplacidus", "Bet Car"), ("Ankaa", "Alp Phe"), ("Algieba", "Gam1Leo"),
    ("Zosma", "Del Leo"), ("Chertan", "The Leo"), ("Porrima", "Gam Vir"),
    ("Gienah", "Gam Crv"), ("Algorab", "Del Crv"), ("Kraz", "Bet Crv"),
    ("Tejat", "Mu  Gem"), ("Mebsuta", "Eps Gem"), ("Alzirr", "Xi  Gem"),
    ("Ruchbah", "Del Cas"), ("Segin", "Eps Cas"), ("Navi", "Gam Cas"),
    ("Mothallah", "Alp Tri"), ("Sheratan", "Bet Ari"), ("Errai", "Gam Cep"),
    ("Pherkad", "Gam UMi"), ("Aljanah", "Eps Cyg"), ("Fawaris", "Del Cyg"),
    ("Alshain", "Bet Aql"), ("Sabik", "Eta Oph"), ("Cebalrai", "Bet Oph"),
]


def parse_bsc5p(path: Path) -> list[dict[str, str]]:
    text = path.read_text(encoding="latin-1").split("\n")
    fields = next(l for l in text if l.startswith("line[1]")).split("=", 1)[1].split()
    start = text.index("<DATA>") + 1
    rows = []
    for line in text[start:]:
        if not line or line.startswith("<"):
            continue
        values = line.split("|")
        rows.append(dict(zip(fields, values)))
    return rows


def bayer(alt_name: str) -> str:
    """'58Alp Ori' -> 'Alp Ori'; 'Alp1Cru' stays."""
    return re.sub(r"^\d+", "", alt_name).strip()


def unit(ra_deg: float, dec_deg: float) -> tuple[float, float, float]:
    ra, dec = math.radians(ra_deg), math.radians(dec_deg)
    return (math.cos(dec) * math.cos(ra), math.cos(dec) * math.sin(ra), math.sin(dec))


def separation_deg(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    dot = max(-1.0, min(1.0, a[0] * b[0] + a[1] * b[1] + a[2] * b[2]))
    return math.degrees(math.acos(dot))


def main(src: Path) -> None:
    rows = parse_bsc5p(src / "heasarc_bsc5p.tdat")
    stars = []
    for r in rows:
        if not r["vmag"] or not r["ra"] or not r["dec"]:
            continue
        v = float(r["vmag"])
        if v > MAG_LIMIT:
            continue
        stars.append({
            "hr": int(r["hr"]),
            "ra": float(r["ra"]),
            "dec": float(r["dec"]),
            "v": v,
            "bv": r["bv_color"],
            "pmra": round(float(r["pmra"] or 0) * 1000),
            "pmdec": round(float(r["pmdec"] or 0) * 1000),
            "bayer": bayer(r["alt_name"]),
        })
    stars.sort(key=lambda s: s["hr"])
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "bsc5-stars.csv").open("w", encoding="utf-8") as f:
        f.write("hr,ra_deg,dec_deg,vmag,b_v,pmra_mas_yr,pmdec_mas_yr\n")
        for s in stars:
            bv = f"{float(s['bv']):.2f}" if s["bv"] else ""
            f.write(f"{s['hr']},{s['ra']:.5f},{s['dec']:.5f},{s['v']:.2f},{bv},{s['pmra']},{s['pmdec']}\n")

    by_bayer: dict[str, dict] = {}
    for s in stars:
        if s["bayer"]:
            by_bayer.setdefault(s["bayer"], s)
    with (OUT / "star-names.csv").open("w", encoding="utf-8") as f:
        f.write("hr,name\n")
        for name, designation in STAR_NAMES:
            star = by_bayer.get(designation)
            if star is None:
                sys.exit(f"no BSC5 star with designation {designation!r} for {name}")
            f.write(f"{star['hr']},{name}\n")

    # Constellation figures: match every vertex to a catalogue star.
    vectors = [(unit(s["ra"], s["dec"]), s) for s in stars]
    lines = json.loads((src / "constellations.lines.json").read_text())
    figures: dict[str, list[list[int]]] = {}
    worst = 0.0
    for feature in lines["features"]:
        for polyline in feature["geometry"]["coordinates"]:
            hrs = []
            for lon, lat in polyline:
                v = unit(lon % 360, lat)
                sep, star = min(((separation_deg(v, w), s) for w, s in vectors if abs(s["dec"] - lat) < 1),
                                key=lambda pair: pair[0])
                if sep > MATCH_TOLERANCE_DEG:
                    sys.exit(f"{feature['id']}: vertex {lon},{lat} is {sep:.3f} deg from the nearest star")
                worst = max(worst, sep)
                hrs.append(star["hr"])
            figures.setdefault(feature["id"], []).append(hrs)
    names = json.loads((src / "constellations.json").read_text())
    with (OUT / "constellations.csv").open("w", encoding="utf-8") as f:
        f.write("abbr,name,rank,label_ra_deg,label_dec_deg,lines\n")
        seen = set()
        for feature in names["features"]:
            abbr = feature["id"]
            if abbr in seen:
                continue
            seen.add(abbr)
            p = feature["properties"]
            # Serpens is one constellation drawn in two parts (Caput, Cauda).
            name = "Serpens" if abbr == "Ser" else p["name"]
            lon, lat = feature["geometry"]["coordinates"]
            polylines = ";".join(" ".join(str(h) for h in line) for line in figures[abbr])
            f.write(f"{abbr},{name},{p['rank']},{lon % 360:.2f},{lat:.2f},{polylines}\n")
    print(f"{len(stars)} stars to V {MAG_LIMIT}, {len(STAR_NAMES)} names, "
          f"{len(figures)} figures, worst vertex match {worst * 3600:.1f} arcsec")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
