# Glossary

Tap-to-explain definitions, in plain language. Written to be short enough to
paste straight into an in-app help sheet (see `docs/ios/HELP-ABOUT.md`).
Each technical term cites a source; where the app computes a number
differently from a cited definition (for example, using sunset/sunrise
instead of a fixed clock time), the entry says so.

## Astronomical, nautical and civil twilight/darkness

The sky gets dark in three stages after sunset, defined by how far the sun
has dropped below the horizon. **Civil twilight** ends when the sun is 6°
below the horizon — by then you need headlights, but you can still make out
the horizon. **Nautical twilight** ends at 12°, when the horizon itself
disappears. **Astronomical twilight** ends at 18°, the point past which the
sun no longer brightens the sky at all — that's "astronomical darkness,"
the darkest the sky gets. Dark Sky uses the sun-below-18° window as its
darkness window; the reverse happens in the same order before sunrise.
Source: [Twilight, U.S. Naval Observatory / timeanddate.com](https://www.timeanddate.com/astronomy/different-types-twilight.html).

## Moon-free minutes

The number of minutes, during astronomical darkness, when the Moon is also
below the horizon. This is Dark Sky's headline number for nightscape and
Milky Way photography, because moonlight washes out the Milky Way's faint
structure the same way a streetlight washes out stars. It's the
intersection of two windows — astronomical darkness and "Moon down" — not
just one or the other. Source: `docs/methods.md` §Moon-free astronomical
darkness, the app's own worked calculation.

## Transparency

How clear the air itself is, independent of clouds — haze, humidity and
aerosols (dust, smoke) all scatter light and dim faint objects even under a
technically "clear" sky. Poor transparency is why a clear night can still
look washed-out and gray instead of black. It matters much more for
deep-sky targets (faint galaxies and nebulae) than for bright nightscape
subjects like the Milky Way core, which is why Dark Sky treats it as
advisory for nightscape but gates deep-sky verdicts on it when data exists.
Source: [Transparency and Atmospheric Extinction, Sky & Telescope](https://skyandtelescope.org/astronomy-resources/transparency-and-atmospheric-extinction/).

## Seeing

How steady the atmosphere is, moment to moment — turbulence blurs and
shimmers a point of light the way heat haze blurs a distant view. Bad
seeing smears fine detail on the Moon and planets and blurs stars into
bigger, softer dots even when the sky is perfectly transparent. It barely
affects wide-field Milky Way shots but matters a great deal for anything
zoomed in — planetary imaging especially. Dark Sky estimates it from
jet-stream wind speed at high altitude (faster winds aloft generally mean
worse seeing), a proxy chosen because it needs no extra data source.
Source: [Seeing & Jetstream Forecast, ChileScope](http://www.chilescope.com/equipment-and-infrastructure/weather-conditions/seeing-jetstream-forecast).

## Terrain horizon / skyline

The real, physical horizon at your shooting spot — ridgelines, hills, trees
— as opposed to the flat mathematical horizon astronomy math assumes by
default. A target that's technically "above the horizon" by the numbers can
still be hidden behind a ridge for another hour. Dark Sky can use a
measured terrain profile (surveyed at a spot) or one computed from public
elevation data, and folds it into the Moon-up and target-visible
calculations so "up" means "actually visible from here," not just
"above 0° altitude." Source: `docs/ios/PLAN.md` M9 — Terrain-aware
darkness, the app's own implementation.

## Forecast age and model run

Every weather number Dark Sky shows says where it came from and how old it
is — for example "HRRR, run 11Z, fetched 7 minutes ago." The **model run**
is when the weather model last recalculated from fresh data (some models
run hourly, some every six or twelve hours); the **age** is how long ago
the app itself fetched that number. An old model run isn't wrong, but it's
missing anything that's changed since — smoke that started, a cloud band
that moved in. Source: `docs/adr/0006-freshness-thresholds.md`, the app's
own freshness convention (fresh / aging / stale / unavailable).

## NPF rule

A formula for the longest camera exposure you can take of the stars before
they visibly smear into short trails, given your camera's pixel size, lens
aperture and focal length, and where in the sky you're pointed. It refines
the older, cruder "500 rule" (500 ÷ focal length = seconds), which ignores
pixel size and declination and was never very accurate. Dark Sky's Tools
calculators implement NPF as the untracked-exposure ceiling; a tracked
mount can go well past it. Source: [The NPF Rule: A Formula for Sharp Star Photos, PetaPixel](https://petapixel.com/2017/04/07/npf-rule-formula-sharp-star-photos-every-time/).

## Star trails

A shot where stars are deliberately allowed to streak into arcs, made by
either one very long exposure or — more commonly today — many shorter
exposures combined afterward by keeping the brightest value at each pixel
across the stack ("lighten" blending). Longer total time makes longer
trails; a trail centered on Polaris (in the northern hemisphere) traces
concentric circles around the celestial pole. Dark Sky's Tools calculators
estimate trail length for a given duration and focal length. Source:
[Star Trails: Tips and Techniques, PhotoPills](https://www.photopills.com/articles/how-shoot-star-trails).

## Stacking

Taking many shorter exposures of the same static scene and combining them
in software, instead of one long exposure. Stacking adds up the faint
signal (stars, nebulosity) while averaging out random noise, and — with
star-based alignment — can reject bad frames like satellite trails or plane
lights that only appear in one exposure. Dark Sky's Capture tool does this
on-device: it aligns frames on detected stars, then combines them with a
sigma-clipped average (or brightest-pixel for trails). Source:
[Image Stacking, Deep Sky Watch](https://www.deepskywatch.com/astrophotography-basics/image-stacking.html).

## ProRAW

An Apple photo format (Adobe DNG-based) that keeps most of the sensor's raw
data — much more than a JPEG or standard HEIC — while still applying some
of the iPhone's computational photography. It gives far more room to adjust
exposure, white balance and detail afterward, at the cost of a much larger
file (tens of megabytes per photo instead of a few). Available on iPhone
Pro models in Settings, and it's a separate on/off setting from Night mode.
Source: [Apple ProRAW support](https://support.apple.com/en-us/119916).

## Field mode

Dark Sky's all-red interface, meant to be switched on outdoors after dark.
It preserves night vision the way a photographer's red headlamp does: the
eye's dark adaptation is far less disturbed by dim red light than by white
or blue light of the same brightness. Field mode also swaps some system
text fields for the app's own red-safe on-screen keypad, since the system
keyboard itself is not red-able. Source: [Dark Adaptation and Red Light, American Academy of Ophthalmology](https://www.aao.org/eye-health/tips-prevention/how-your-eyes-adjust-to-light-dark); `docs/ios/DESIGN.md`.

## Bortle / SQM

Two different ways of describing how dark a sky is. The **Bortle scale** is
a 9-level descriptive scale (1 = darkest pristine sky, 9 = inner-city sky)
based on what you can see by eye — the Milky Way's visibility, faintest
visible stars, and so on. **SQM** (Sky Quality Meter) is an instrument
reading in magnitudes per square arcsecond — a *higher* SQM number means a
*darker* sky, the opposite direction from Bortle's numbering. The mapping
between the two is approximate; the original Bortle scale never defined
exact SQM boundaries, so treat any Bortle-to-SQM conversion as a rough
guide, not a formula. Source: [Bortle Scale Guide, npfcalculator.com](https://www.npfcalculator.com/bortle-scale).
