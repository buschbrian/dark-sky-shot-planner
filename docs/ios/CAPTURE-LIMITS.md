# iPhone 18 Pro Max capture limits (measured)

Measured on the owner's iPhone 18 Pro Max (iPhone19,3, iOS 27.2 build
24B5089g) on 2026-09-26 by the Debug probe (`-CameraProbe YES`,
`ios/App/Capture/CameraProbe.swift`). The full per-format output is in
`iphone18promax-camera-probe.json`. Formats and ranges come from
`AVCaptureDevice.Format` with no session running. RAW lists come from an
idle session that was never started, with camera permission granted. ADR-0011
says these numbers drive the design; none of them is taken from marketing.

## Per back camera

| | Main (wide) | Ultra wide | Telephoto |
|---|---|---|---|
| Formats | 72 | 65 | 65 |
| **Longest single exposure** | **1.0 s** (every format) | **1.0 s** (every format) | **1.0 s** (every format) |
| Shortest exposure | 14 µs | 14 µs | 14 µs |
| ISO range, best astro format | 55–12,320 | 15–3,600 | 15–7,680 |
| Apertures (iOS 27 `recommendedLensApertureStops`) | f/1.48, 1.8, 2.8, 4.0 | f/2.2 fixed | f/2.8 fixed (2.7988) |
| Fully manual `setExposureModeCustom(lensAperture:duration:iso:)` at 1 s and max ISO | yes, at all 4 stops | yes (fixed stop) | yes (fixed stop) |
| Bayer RAW | none on any format | none | none |
| Apple ProRAW | `l64r` → DNG, 2 formats | `l64r` → DNG, 2 formats | `l64r` → DNG, 2 formats |
| Max photo size, best astro format | 8064×6048 (also 5712×4284, 4032×3024) | same | same |
| Field of view, best astro format | 70.7° | 103.6° | 19.0° |
| Focus lock at a custom lens position | yes (0–1; 1 is the far end, which Apple says is not infinity) | yes | yes |
| Minimum focus distance | 200 mm | 20 mm | 1,160 mm |
| Low-light boost | not supported | not supported | not supported |
| Shutter-sound suppression | supported | supported | supported |

The **best astro format** on each camera is the 4032×3024 video format
(index 69 `420v` / 70 `420f` on the main camera, 62/63 on the others). It
is the only one offering ProRAW and 48 MP stills. On the main camera it is
also the only one reaching ISO 12,320: the others stop at 5,280 or lower.
Its frame-rate range is 1–30 fps, so a 1 s frame is the longest the format
streams. The app picks this format (`CaptureEngine.bestFormat`).

## What this means for the design

- The iPhone's single-frame ceiling for a third-party app is **1 s**. That is
  far below the NPF limit for these lenses (about 8.6 s for the main camera,
  from the EXIF of a real frame: see §Verified capture). So every capture
  is a sequence of 1 s frames. The Camera app's 10–30 s Night mode is
  Apple's own multi-frame pipeline and is not available to apps.
- **RAW means ProRAW.** No Bayer RAW is listed on any format. The option is
  Apple ProRAW: a demosaiced, scene-referred "linear DNG". Apple documents
  that `photoQualityPrioritization = .speed` makes stills use the locked
  custom exposure instead of multi-image fusion, and the app sets `.speed`.
  ProRAW still passes through Apple's own raw pipeline, which the app cannot
  inspect or switch off.
- **The main camera, wide open (f/1.48), is the astro camera.** It has the
  most light, the highest ISO ceiling and the only variable aperture. The
  ultra wide (f/2.2, ISO ≤ 3,600) suits wide star-trail frames. The
  telephoto (f/2.8, 19°) is for the moon.
- Focus has no "infinity" value to set. The capture screen locks a lens
  position chosen with a magnifier and a star half-flux-radius readout, and
  remembers it.

## Verified capture (2026-09-27, indoors)

- A 5-frame main-camera sequence at 1.0 s, ISO 800 and f/1.48 gave 4032×3024
  ProRAW DNGs whose EXIF reads 1.0000 s. Their sensor timestamps are 1.00 s
  apart, so each is a new exposure. Zero shutter lag is off, requests are
  paced one exposure apart, and every frame's timestamp is checked, because
  with ZSL on the output returned five "1 s" frames in 0.6 s from its ring
  buffer.
- The phone stacked them in 2.8 s into a 16-bit linear-sRGB TIFF (peak
  memory 805 MB).
- On 20 synthetic 12 MP frames, star detection takes 0.079 s per frame,
  registration 0.013 s for all of them, the sigma-clipped mean 6.8 s and
  the trail maximum 0.9 s.
- The EXIF focal length of 6.93 mm (3.46 crop, 2.48 µm pitch) gives an NPF
  limit of 8.6 s at k = 1.

Details and the remaining owner checks are in the PLAN.md log entry for M12.
