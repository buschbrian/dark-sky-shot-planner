# First outing with the phone

A short, practical walk-through for the owner's first (or next) shoot night
with Dark Sky on the phone. It names the app's own screens and buttons by
their visible labels, not by feature names. Some of this — the shot window
on Tonight, a real dark-site compass check, a night-sky capture — is
**unverified**: see `docs/ios/CAPABILITIES.md` for what has and hasn't been
checked on a phone at a dark site yet.

## Before leaving, with signal

1. **Set the place.** Tonight → **Choose a location** → **Use my location**,
   or type coordinates / paste a share link in the sheet that opens
   (`LocationSheet`). Confirm the coordinates and time zone line look right
   for where you're headed, not where you are now.
2. **Download an offline map area.** Map tab → the **Offline basemap**
   section of the panel → **Keep this area offline** for the visible view,
   or **Keep `<spot name>` offline** for a saved spot (a 10×10 km area
   around it). This keeps Topo and Dark relief tiles (they share the same
   download) and terrain; Imagery is optional and roughly doubles the size.
   Do this over Wi-Fi before you leave — there is no offline map if you
   skip it.
3. **Check Tonight and the shot window.** Read the headline (moon-free
   minutes, verdict, limiting factor) and the darkness/moon/Galactic Center
   numbers below it. **As of this writing, a per-target shot window and the
   sky-events list are not yet reachable from Tonight** — the code exists
   but no screen shows it (`docs/ios/CAPABILITIES.md`). Until that lands,
   use the Tools tab's calculators and the Map's azimuth lines for the
   "where exactly does it clear the ridge" question.
4. **Note forecast ages.** Every conditions number on Tonight and Week
   carries a source and an age (for example "from the conditions Worker,
   fetched 7:25 AM"). Before you lose signal, open **Every factor** and
   note each model's run time — that is the freshest picture you will have
   once you're offline.

## At the site

1. **Turn on field mode.** Tap the moon/stars icon (accessibility label
   "Field mode") on Tonight, Week, Spots or Tools; the whole app dims to
   red. On the current build this does **not** survive a relaunch — if you
   force-quit or the phone restarts the app, you'll need to turn it back
   on. Set brightness with the field brightness dock that appears once
   field mode is on.
2. **Calibrate the compass.** Open Sky. If the figure-8 guide appears
   ("Wave the phone in a slow figure 8, turning it as you go, away from the
   car and tripod"), follow it away from the vehicle and any metal tripod.
   Then tap **Calibrate** and align on the Moon, a planet, a bright star, or
   a saved peak — the panel that opens lists whichever of those are
   available right now. **This alignment step has not been checked at a
   real dark site**; treat the on-screen heading as approximate until it
   has been.
3. **Use Sky.** With calibration done, Sky overlays the Milky Way band, the
   Galactic Center's path, the Moon and planets, and the terrain horizon
   (when the spot has one) on the live camera view. The heading badge and
   an "approximate" note tell you when the app itself isn't confident in
   the alignment — believe that note over the picture.

## Capture

1. **Tripod first.** Both capture paths below assume a stable tripod and
   locked/manual focus; a shaky mount ruins either one.
2. **Two paths — pick one:**
   - **Apple Camera, Night mode.** Use the stock Camera app. Night mode
     turns on automatically in low light on supported iPhones and lets the
     shutter stay open longer on a tripod; keep Live Photos and flash off
     (either one disables Night mode). See Apple's own guide for exactly
     how it behaves on your phone —
     [Night mode](https://support.apple.com/en-us/102519). Turn on ProRAW
     first in Settings if you intend to edit later; it uses much more
     storage per photo — see
     [ProRAW](https://support.apple.com/en-us/119916). Dark Sky does not
     control or promise a fixed exposure time here; that is entirely
     Apple's camera pipeline.
   - **Dark Sky capture.** Tools tab → **Tripod capture**. Set focus
     first: aim at a bright star or distant light and move the **Lens
     position** slider until the stars in the magnifier are smallest (the
     on-screen half-flux radius, HFR, is lowest there). Set **Exposure**
     and **ISO**, and the sequence's frame count and format under
     **Sequence**. Start the run; **Stop and stack** ends it and stacks
     what was shot, **Cancel** ends it and stacks nothing — either way
     every frame is kept. **This has only been tested indoors on the
     owner's phone**, where fewer than half the frames aligned on "stars"
     and the stack fell back to unaligned; a real outdoor star field has
     not been tried yet (`docs/ios/PLAN.md` M12, `docs/ios/CAPABILITIES.md`).
3. **Focus matters more than any setting.** Whichever path you use, check
   focus with a magnified live preview before starting a real sequence,
   not after.

## Back home

1. **Log forecast vs. actual.** Compare what the models said (cloud cover,
   the limiting factor Tonight named) against what you actually saw, and
   write it in `docs/ios/PLAN.md` §Log with the build revision, the way
   past field checks have been recorded there. This is how the verdict
   thresholds get tuned — not by editing the code, but by writing down
   when a real night disagreed with the app.
2. Frames and stacks from Dark Sky capture land in Files → **On My
   iPhone → Dark Sky → Captures → `<folder>`**; the finished stack (and,
   separately, all originals) also gets offered to Photos.
