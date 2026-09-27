# iOS design system

One product, one voice: a clean, understated night-science instrument. Code
lives in `ios/App/Shared/Design/`; open the Debug gallery with the launch
argument `-DSTab gallery` (or the `DesignGallery` previews) to see every piece
in both palettes. Every agent building iOS views uses these; do not add
one-off colors, cards, buttons, switches or headers.

## Rules

1. **Answer first, then evidence.** The top of a screen says the answer (a
   number, a verdict and its limiting factor). Method notes, long sources and
   caveats go below or behind `MoreInfo`.
2. **Every number carries its source and age** (ADR-0006): put a
   `ProvenanceChip` under it. Values computed on the phone use
   `SourceInfo.onDevice`.
3. **Missing never reads as good.** A nil value is `UnavailableValue` (or a
   `MetricTile` with `value: nil`), never 0, never blank.
4. **Colors come from `@Environment(\.palette)`**, never a literal. Status
   colors (`good`, `marginal`, `poor`) mean go / marginal / no-go only; chart
   series use `palette.data`. Shape or dash always backs up color, because
   field mode tells things apart by brightness only.
5. **Field mode is pure red for everything the app draws.** Every token in
   `Palette.field` has green = blue = 0. System glass cannot be recolored, so
   in field mode: hide toolbar glass (`palette.toolbarGlass`), use
   `floatingSurface` rather than `.glassEffect`, and avoid the system
   keyboard (use the in-app keypads). Sheets and full-screen covers are
   separate presentations: end them with `.sheetPresentation(palette)`.
6. **Liquid Glass only for the floating layer** in standard mode (toolbars,
   the tab bar, map overlays via `floatingSurface`). Content is solid cards.
7. **SF Pro only, no serif.** Numbers that update use tabular figures;
   provenance uses SF Mono (`.dsData`). Everything follows Dynamic Type;
   overlays on a map or camera may cap at `.xLarge`.
8. **Accessibility.** Controls are at least 44 pt (`DS.minTarget`); charts
   and custom controls give one VoiceOver element with a spoken summary;
   custom switches keep `accessibilityRepresentation`.

## Tokens (`Tokens.swift`, `Palette.swift`)

| Token | Values |
|---|---|
| `DS.Space` | xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32; `screen` 16, `cardGap` 12, `card` 16 |
| `DS.Radius` | `control` 10 · `card` 16 · `bar` 4 (continuous corners) |
| Type | `.dsNavTitle` headline · `.dsTitle` title3 semibold · `.dsHeadline` · `.dsBody` · `.dsCallout` · `.dsFootnote` · `.dsMetric` title3 medium tabular · `.dsData` caption mono · `.eyebrow(palette)` uppercase section label · `DisplayNumber` hero |
| Palette | `background`, `surface` (cards), `raised` (controls on cards), `hairline`, `primary`, `secondary`, `tertiary`, `accent`, `onAccent`, `good`/`marginal`/`poor`, `isField` |
| `palette.data` | `sun`, `moon`, `galacticCenter`, `moonFree`, `moonlit`, `darkness`, `twilight`, `grid`, `axisLabel`, `cell` |

Standard contrast on `surface`: primary 15.6:1, secondary 8.1, tertiary 5.0,
accent 8.4. Field: primary 5.1, secondary 4.0 (pure red cannot go higher).
Sun, GC and moon-free pass the dataviz validator (all pairs, CVD ΔE ≥ 8.7);
the moon is a neutral silver and always the solid line.

## Components

| Component | Use for |
|---|---|
| `SectionCard(title) { }` | Every grouped surface. The title is an eyebrow; `accessory:` puts a control on the right. |
| `MetricTile` | A labelled value + unit + detail + provenance; nil value reads unavailable. |
| `ProvenanceChip(info:)` | Source · model · run · age, with a freshness glyph; the word shows unless fresh. |
| `SourceInfo` | Its data. `SourceInfo(provenance)` converts a SkyCore `Provenance`. |
| `StatusBadge(level:qualifier:)` | Go / marginal / no-go / unavailable, glyph + word. The limiting factor goes in the line under it. |
| `UnavailableValue(reason:)` | A missing value, with an optional reason. |
| `EmptyState` | An empty screen: symbol, title, one sentence, one action. |
| `DataStatusLine` | One line about where a screen's data came from (`ConditionsSourceStatus`). |
| `FactRow`, `MoreInfo` | Spec-sheet rows; disclosure for secondary detail. |
| `NightBar` | The signature strip: twilight, moonlit darkness, moon-free windows, now. |
| `DSChart`, `SeriesKey` | Swift Charts axes/grid and the sun/moon/GC strokes (color + dash). |
| `ActionButtonStyle(.primary / .secondary / .quiet)` | All buttons in content. |
| `PaletteToggleStyle()` | The only switch. |
| `ChoiceRow`, `KeypadKeyStyle`, `KeypadMetrics`, `PaletteProgress`, `Disclosure` | Segmented choices, in-app keypads, progress, list chevrons. |
| `screenChrome(title) { actions }` | Every tab screen's header: title (or a control via `principal:`), optional `leading:` context action, actions, then the field-mode toggle, always last on the right. `pushed: true` for pushed pages. |
| `sheetChrome(title, cancel:, confirm:)` + `.sheetPresentation(palette)` | Every sheet. |
| `floatingSurface(palette, shape:)` | Anything floating over a map or camera. |
| `FieldDock`, `BrightnessControl` | Field mode's palette tab bar with the one-hand brightness slider (shell only). |

## Status voice (`Voice.swift`)

- **unavailable**: no value. **stale**: older than its freshness window, shown
  with its age. **last good copy**: the latest fetch failed, so the previous
  value is shown with its age. **estimated**: worked out without the preferred
  input (flat horizon, this phone's time zone). **not set up**: an optional
  service this build has no address for; not an error.
- Data ages read "3 h old" (`Voice.age`); events read "3 h ago" (`Voice.ago`);
  model runs read "18Z" (`Voice.run`).
- The Worker is "the live conditions service". It is "didn't answer" only
  when one is configured and fails; with none configured it is "not set up".
  Route SkyCore reason strings through `Voice.reason(_:workerConfigured:)`.

## Field-mode check

`DesignTourTests` screenshots every tab and sheet in both palettes (set
`TEST_RUNNER_DS_SHOTS=/folder` to save PNGs) and fails a field screenshot
with any pixel whose green or blue exceeds 12, skipping only the
home-indicator strip. Add your screen to it.
