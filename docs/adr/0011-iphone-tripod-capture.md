# ADR-0011: iPhone capture for tripod astrophotography

**Status:** accepted · **Date:** 2026-09-26

## Context

The owner wants the field companion to help people take better night photos
with the iPhone itself, mounted on a tripod, not only to plan shots for a
dedicated camera. The Camera app's Night mode reaches 10 s or more on a
tripod, but it is Apple's computational pipeline and is not available to
other apps. A third-party app gets `AVCaptureDevice` custom exposure, which is
bounded per format by `activeFormat.maxExposureDuration` (commonly around a
second; not assumed here), an ISO range, manual focus (`lensPosition`), RAW
capture through `AVCapturePhotoOutput`, and, on the iPhone 18 Pro models,
aperture through `setExposureModeCustom(lensAperture:duration:iso:)` where a
format supports it (`docs/ios/ASTRONOMY-APP-RESEARCH-2026-09-26.md`). Existing
"bulb mode" apps get long effective exposures by shooting many frames and
combining them.

## Decision

Add capture to the app as its own milestone, deterministic-first:

1. **Measure before designing.** A capability probe runs on the owner's
   phone and records, per camera and format: maximum and minimum exposure,
   ISO range, supported apertures, RAW and ProRAW formats, focus range and
   frame rates. Those numbers go into `docs/ios/` and drive the design; no
   limit is assumed from memory or marketing.
2. **Long exposures are sequences.** Shoot the longest usable frames the
   format allows at fixed ISO, focus locked at infinity, and keep every
   original frame (RAW/DNG where supported). Combine them by registering
   frames on stars (translation, and rotation for longer spans) and averaging
   with outlier rejection (for example sigma clipping, which also removes
   satellites and aircraft). Star trails are the maximum instead of the mean.
3. **No generative or learned enhancement.** The stack is signal averaging,
   reproducible from the saved frames. No AI denoise, sky replacement or
   "enhance". This matches the owner's rule for Dust & Starlight photographs.
4. **Planning feeds capture.** The iPhone's own sensor and lens are a gear
   profile (M10), so NPF and trail limits apply to it. The target and time
   come from Tonight and Sky, and the frame count comes from the stacking
   calculator.
5. **Everything stays on the phone.** Results and frames go to the photo
   library with metadata; nothing is uploaded.

## Consequences

- Capture can only be tested on a physical iPhone; the simulator has no
  camera. Each capture change needs an owner check at night.
- Long sequences are heavy on battery, heat and storage: throttle under
  thermal pressure and show the storage a sequence will use before it starts.
- Registration is real computer vision work (star detection, matching,
  transforms); it lives in SkyCore as pure, tested functions over pixel
  buffers so it can be checked on synthetic star fields.
- Field mode applies to the capture screen, but the saved photos are never
  tinted.
