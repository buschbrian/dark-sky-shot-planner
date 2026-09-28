# Dark Sky on the App Store: listing, data licences and money

Research only, 2026-09-27. Repo facts come from `/Users/brianbusch/Developer/wt-dark-sky-next` at commit `9f12c2d` on `local/ios-integration`. Every web link was checked on **2026-09-27** unless a line says otherwise. Anything I could not confirm on a primary page is marked **(unverified)** and listed again at the end.

## Summary

Dark Sky can't be listed yet, and nothing about that is hard. The app is signed by a free Personal Team, and free teams can't use TestFlight or the App Store. The paid Apple Developer Program costs $99 a year. If Brian enrolls as an individual, "Brian Busch" appears as the seller. "Dust & Starlight" can appear only if it becomes a legal entity such as an LLC with a D-U-N-S number, because Apple does not accept DBAs. The repo also lacks the usual store items: an app icon, a privacy manifest, a privacy policy and support page, an encryption key in Info.plist, a credits screen, and removal of sample-fixture layers. The data side matters more. Any paid, subscription or promotional release counts as commercial use of Open-Meteo, so it needs a paid key ($29/month for 1M calls, $99/month for 5M). The app's direct keyless Open-Meteo fallback has to go, and so do 7Timer! (non-commercial only) and, unless its author agrees, the NPF rule's non-commercial terms. With those fixed, running costs are small. I estimate about $40 a month at 100 daily users, about $110 at 1,000 and about $400 at 10,000 if every user gets live conditions. They are lower if only subscribers do. My recommendation is a free app, whose on-device planning, Sky view, tools and capture never touch the paid APIs, plus one auto-renewing "live conditions" subscription (for example $19.99 a year, one-week free trial, Family Sharing on). That model ties data cost to paying users. At the 15% Small Business rate it breaks even at roughly 26 subscribers. The fallback is a one-time paid app priced like PhotoPills and The Photographer's Ephemeris ($9.99–$10.99), with the forecast cost carried by new sales.

---

## 1. Getting listed, step by step

### 1.1 Where the app stands today (checked on this Mac)

| Fact | Evidence |
|---|---|
| Team `25P35HU7ZH` is a **free Personal Team**, not a paid membership | `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` → `teamName = "Brian Busch (Personal Team)"`, `teamType = "Personal Team"`, `isFreeProvisioningTeam = 1` |
| Its provisioning profiles last 7 days | `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`: `iOS Team Provisioning Profile: com.brianbusch.darksky` created 2026-09-26, expires 2026-10-03 (same for `.widgets`, `.uitests`) |
| Only a development identity exists | `security find-identity -v -p codesigning` → one `Apple Development: …` identity, no `Apple Distribution` identity |
| Bundle ID and App Group | `ios/Config/Local.xcconfig` (gitignored): `BUNDLE_ID_PREFIX = com.brianbusch.darksky`; App Group `group.com.brianbusch.darksky` |

A Personal Team can't use App Store Connect, TestFlight or App Store distribution. Apple's membership comparison marks all three unavailable for free accounts ([compare memberships](https://developer.apple.com/support/compare-memberships/)). Apple's QA1915 also says a Personal Team can't sign an app for App Store submission ([QA1915](https://developer.apple.com/library/archive/qa/qa1915/_index.html), seen through a search snippet only).

### 1.2 Apple Developer Program: individual or organization

- **Cost:** "99 USD per membership year" ([What's included](https://developer.apple.com/programs/whats-included/)).
- **Individual:** "If you're an individual or sole proprietor/single-person business, your personal legal name will be listed as the seller on the App Store." Enrollment completes after purchase, and Apple says to contact it if confirmation hasn't arrived within 24 hours ([Enrollment](https://developer.apple.com/support/enrollment/)).
- **Organization:** "the legal entity name will be listed as the seller". It needs legal entity status ("We don't accept DBAs, fictitious businesses, trade names, or branches"), a D-U-N-S Number, a work email on the organization's domain, and "a publicly available and functional" website on that domain. Social-media pages or placeholder sites are refused ([Enrollment](https://developer.apple.com/support/enrollment/)).
- **Switching later:** an individual account can be converted to an organization account by contacting Apple ([Enrollment](https://developer.apple.com/support/enrollment/)).
- **Fee waiver:** this is for nonprofits, schools and government only, and explicitly not for "an individual, sole proprietor, or single-person business" ([Fee waivers](https://developer.apple.com/help/account/membership/fee-waivers/)).

**What Dust & Starlight would need.** For "Dust & Starlight" to appear as the seller, it must be a legal entity such as a Utah LLC. It also needs a D-U-N-S number, an email address on its own domain, and its working website. A DBA registration alone is not enough. The simpler path is to enroll as an individual now, ship as "Brian Busch", and convert later if an LLC is formed. The D&S site Worker (`dust-and-starlight-site`, in the same Cloudflare account) could supply the domain and website. I did not check whether its domain would meet Apple's test.

**Unknown:** whether a paid individual enrollment reuses the Personal Team ID `25P35HU7ZH` or issues a new one, and whether `com.brianbusch.darksky` stays registrable. If Xcode reports the identifier as unavailable, choose a new bundle ID before creating the App Store Connect record, because the bundle ID can't be changed after the first build upload ([App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)). **(unverified)**

### 1.3 App Store Connect setup

1. Accept the current agreements. Then choose Apps › "+" › New App and enter the platform, name, primary language, bundle ID, SKU and user access ([Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)).
2. Register the explicit App IDs `…darksky` and `…darksky.widgets` with the App Groups capability and the group `group.<prefix>`. Both targets already declare it (`ios/project.yml`).
3. Field limits ([App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information); [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)):

| Field | Limit / rule |
|---|---|
| Name | 30 characters, unique. Guideline 2.3.7 bars keyword stuffing and trademarked terms ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)) |
| Subtitle | 30 characters |
| Promotional text | 170 characters, editable without a new build |
| Description | 4,000 characters, plain text |
| Keywords | 100 bytes, each keyword longer than 2 characters, no other apps' or companies' names |
| Support URL | Required. "must lead to actual contact information (legal address, email address, telephone number), as may be required by local law" |
| Privacy Policy URL | "Required for iOS and macOS apps" |

**Name risk.** A bare "Dark Sky" is risky:
- Apple bought the Dark Sky weather app and shut it down ([Wikipedia: Weather (Apple)](https://en.wikipedia.org/wiki/Weather_(Apple)), secondary source). A USPTO record "DARK SKY — Apple Inc." shows up in searches, but the record wouldn't load. **(unverified)**
- DarkSky International, the nonprofit whose certified places the app lists, says its name may not be used without permission ([DarkSky terms of use](https://darksky.org/about/legal/terms-of-use/), seen through a search summary). **(unverified)**
- Live US apps already use the words: "Dark Sky Meter" ([id602989060](https://apps.apple.com/us/app/dark-sky-meter/id602989060)) and "Light Pollution Map - Dark Sky" ([id1200379779](https://apps.apple.com/us/app/light-pollution-map-dark-sky/id1200379779)).

Guideline 5.2.1 bars using others' trademarks ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)). Pick a distinct store name, keep "Dark Sky" out of the first word, and test availability when creating the record.

### 1.4 TestFlight

- **Internal testers:** up to 100 App Store Connect users on your team. **External testers:** up to 10,000. When the first build is added to an external group, it goes to App Review. Builds can be tested for up to 90 days ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview); [TestFlight](https://developer.apple.com/testflight/)).
- Public links for external groups exist ([TestFlight](https://developer.apple.com/testflight/)).
- **Licensing note:** Open-Meteo's terms count "integrating our service into commercial products or promotional activities" as commercial ([terms](https://open-meteo.com/en/terms)). A public beta of an app that will be sold falls under that. Subscribe to the paid key before the first external group.

### 1.5 Required assets

| Asset | Spec | Source |
|---|---|---|
| Screenshots | 1–10 per localization, JPEG or PNG, no alpha | [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) |
| 6.9″ iPhone (iPhone 18 Pro Max, 17 Pro Max, Air, 16 Pro Max …) | 1320 × 2868, 1290 × 2796 or 1260 × 2736 portrait | same |
| 6.5″ iPhone | 1284 × 2778 or 1242 × 2688. Required only if no 6.9″ set is provided; smaller sizes scale down from 6.9″ | same |
| iPad | Not needed: `TARGETED_DEVICE_FAMILY: "1"` (iPhone only) in `ios/project.yml` | repo |
| App preview (optional) | Up to 3 per localization per device size, up to 30 s | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information); [Product page](https://developer.apple.com/app-store/product-page/) |
| App icon | A 1024 × 1024 App Store icon in the asset catalog; Icon Composer can build layered iOS 26 icons | [Icon Composer doc](https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer) (search snippet) **(unverified detail)** |
| Description, keywords, support URL, privacy policy URL | See 1.3 | — |

The existing UI test `TonightTests.testScreenshotTour` (`docs/ios/CAPABILITIES.md`) can produce the 6.9″ set on an iPhone 17 Pro Max simulator. Screenshots must not show the "sample data" fixture layers (see 1.9).

### 1.6 Age rating, export compliance, content rights, EU trader status

- **Age rating.** Ratings are now 4+, 9+, 13+, 16+ and 18+, with new questions. The deadline to answer them for existing apps was 2026-01-31 ([news ks775ehf](https://developer.apple.com/news/?id=ks775ehf); [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)). With no user-generated content, web browsing, chat or mature themes, Dark Sky should rate 4+. That is my inference.
- **Export compliance.** Encryption built into the OS, such as HTTPS through `URLSession`, is typically exempt. Setting `ITSAppUsesNonExemptEncryption = NO` in Info.plist skips the per-build question ([ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption); [encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations); both via search snippets). The key is missing today: it is in neither `ios/App/Info.plist` nor the built `DarkSky.app/Info.plist`.
- **Content rights.** App Store Connect asks whether the app contains, shows or accesses third-party content. Answer yes, because it shows basemap tiles and weather and catalog data. Apple may ask for proof of rights. Guideline 5.2.2 says: "ensure that you are specifically permitted to do so under the service's terms of use. Authorization must be provided upon request" ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)). `docs/data-licensing.md` is that evidence once section 2 is resolved. (The exact wording of the question is **unverified**.)
- **EU Digital Services Act.** Every developer must declare trader status, even without EU distribution. Traders have an address, phone and email published on EU product pages. Individuals may give "Address or P.O. Box" ([DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)). Use a P.O. box so a home address in Millcreek is never published. Alternatively, leave out EU storefronts at first.

### 1.7 Privacy: nutrition label and privacy manifest

**Apple's definitions** ([App privacy details](https://developer.apple.com/support/app-privacy-on-the-app-store/)):
- "Collect" means transmitting data off the device in a way that allows access "for a period longer than what is necessary to service the transmitted request in real time".
- Precise location has three or more decimal places. Location coarsened before it leaves the device can be declared as Coarse Location.
- Tracking means linking with third-party data for advertising, or sharing with data brokers.

**Proposed label** (my reading of the code and those rules):

| Question | Answer | Why |
|---|---|---|
| Used to track you | None | No ads, no SDKs, no data brokers |
| Coarse Location | **Collected, not linked to you, App Functionality** (the conservative answer) | The app rounds coordinates to 0.05° before calling the Worker (ADR-0010 §2, enforced server-side). The Worker keeps cached forecasts per cell for up to a week (`docs/ios/PLAN.md` §Behaviour), and Workers Logs is on (`observability.enabled: true` in `worker/wrangler.jsonc`). I could not confirm which request fields Workers Logs keeps. If Brian proves nothing request-level is retained, "Data Not Collected" may be defensible. |
| Precise Location | Not collected | Never leaves the phone |
| Photos, User Content | Not collected | Captures go to the local photo library and Files (ADR-0011 §5) |
| Identifiers, Usage, Diagnostics | Not collected | No analytics or crash SDK in `ios/project.yml` |
| Purchases | Not collected, if StoreKit 2 entitlement checks stay on the device | My inference **(unverified)** |

The privacy policy should also say that map tiles come straight from USGS, and AWS for terrain. Those servers see the device IP and the map area being viewed. So does NASA GIBS, if its planned imagery is added. That is true of every tile map and is worth one sentence.

**Privacy manifest.** No `PrivacyInfo.xcprivacy` exists in `ios/App` or `ios/Widgets`; `find` found only MapLibre's. The reason codes below come from Apple's reason list ([NSPrivacyAccessedAPITypeReasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)) and the covered-API rules ([Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)).

| Category | Where the app uses it | Reason to declare |
|---|---|---|
| User defaults | `@AppStorage` in `App/Capture/CaptureScreen.swift`; `UserDefaults.standard` in `App/DarkSkyApp.swift` and `App/Capture/*` | **CA92.1**: "information that is only accessible to the app itself". The widget shares a JSON file (`Widgets/Shared/SharedSpot.swift`), not app-group defaults, so 1C8F.1 is not needed |
| File timestamp | `contentModificationDateKey` and `attributesOfItem` on the map cache in `App/Map/MapData.swift` | **C617.1**: "files inside the app container, app group container…" |
| Disk space | `volumeAvailableCapacityForImportantUsageKey` in `App/Capture/CaptureModel.swift:407`. Capture refuses to start with "Not enough free space" (line 425) | **E174.1**: "check whether there is sufficient disk space to write files". Add **85F4.1** if the planned "Storage used" screen shows free space |
| System boot time | Only `CACurrentMediaTime()` (map timing). Apple's covered list names `systemUptime` and `mach_absolute_time`, not `CACurrentMediaTime` | None needed for the app's own code. MapLibre declares 35F9.1 itself |
| Tracking | — | `NSPrivacyTracking = false`, no tracking domains |
| Collected data | See the label above | `NSPrivacyCollectedDataTypeCoarseLocation`, not linked, not tracking, App Functionality |

MapLibre 6.31.0 ships its own manifest (FileTimestamp C617.1, SystemBootTime 35F9.1, UserDefaults CA92.1, no tracking). I read it from `ios/build/SourcePackages/artifacts/.../MapLibre.framework/PrivacyInfo.xcprivacy`. MapLibre is not on Apple's list of SDKs that must ship a signed manifest ([third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements)).

### 1.8 Permission strings and background modes

Taken from `ios/project.yml` and `ios/App/Info.plist`:

| Key | Present | Comment |
|---|---|---|
| `NSLocationWhenInUseUsageDescription` | Yes: "…Precise coordinates never leave the phone." | Accurate, since only the rounded cell leaves the phone. No "Always" key and no background location, which is correct. A manual place (location sheet, map long-press) works without permission, which satisfies 5.1.1(iv) |
| `NSCameraUsageDescription` | Yes | Covers the Sky overlay and Capture |
| `NSPhotoLibraryAddUsageDescription` | Yes | The app requests `.addOnly` (`CaptureModel.swift:802`). No read-access key is needed |
| `NSMotionUsageDescription` | Yes | Harmless. Core Motion device motion may not strictly need it **(unverified)** |
| `UIBackgroundModes: [fetch]` + `BGTaskSchedulerPermittedIdentifiers` | Yes | Matches `BGAppRefreshTask` in `App/Alerts/SpotRefresh.swift`. Guideline 2.5.4 allows background services "only … for their intended purposes" ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)). A forecast refresh that posts a local notification fits |
| Notifications | Requested at runtime (`SpotRefresh.swift:148`) | Local only; no push entitlement is needed |
| `NSAppTransportSecurity › NSAllowsLocalNetworking` | Yes | No local-network code exists yet (smart-telescope handoff is future, ADR-0013). Remove it until needed, and add `NSLocalNetworkUsageDescription` then |
| `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` | Yes | Exposes Captures in Files, which is intended |
| `ITSAppUsesNonExemptEncryption` | **Missing** | Add `NO` |

### 1.9 Review-guideline risks specific to Dark Sky

| Risk | Guideline (quoted from [Guidelines](https://developer.apple.com/app-store/review/guidelines/)) | Status and mitigation |
|---|---|---|
| Location use | 5.1.5: "only when it is directly relevant … notify and obtain consent before collecting, transmitting, or using location data" | Low. When-in-use only, clear string, manual fallback. The privacy policy must say the rounded cell goes to the Worker |
| Minimum functionality | 4.2: features "that elevate it beyond a repackaged website" | Low. Native AR Sky, capture, widget, offline maps and background alerts go far beyond the web app |
| Completeness and placeholders | 2.1 (final, complete builds) and 2.3 (accurate metadata) | **Medium.** The About screen is one disabled "Sync spots with iCloud" toggle (`App/About/AboutScreen.swift`). The light-pollution and PAD-US layers are sample fixtures (`docs/ios/CAPABILITIES.md`). Hide the fixture layers and the dead toggle in release builds, or ship real data |
| "Go / No-go" wording | No clause in the fetched guidelines covers weather or outdoor-safety claims. 1.4.1 is about medical accuracy claims **(no weather clause found)** | Low for review, real for liability. The NWS says its data is "as is" with no warranty ([NWS disclaimer](https://www.weather.gov/disclaimer)). Say "for photography" next to the verdict and add a line that it is not a safety forecast, with a pointer to NWS for hazards. Don't claim accuracy until the dark-site checks in `CAPABILITIES.md` are done |
| Data attribution | 5.2.2 (permission for third-party services); CC BY 4.0 for Open-Meteo requires credit, a licence link and an indication of changes ([licence](https://open-meteo.com/en/licence)) | **Medium.** The app shows provenance chips ("Open-Meteo, HRRR") but has no credits screen with licence links. MapLibre BSD-2 and d3-celestial BSD-3 require the notice in the binary's documentation ([MapLibre](https://github.com/maplibre/maplibre-gl-native-distribution); [d3-celestial LICENSE](https://github.com/ofrohn/d3-celestial/blob/master/LICENSE)). Build the "Credits and licenses" section already specified in `docs/ios/HELP-ABOUT.md` §6 |
| Widget | 2.5.16: "Widgets … should be related to the content and functionality of your app"; 4.4: extensions "may not include marketing, advertising, or in-app purchases" | Low. The widget shows tonight's verdict. Never put a paywall or upsell inside the widget |
| Background refresh | 2.5.4 (see 1.8) | Low. Don't describe alerts as guaranteed; ADR-0010 already calls them best-effort |
| Privacy policy in the app | 5.1.1(i): a link "within the app in an easily accessible manner" | **Missing.** Add it to About |
| Subscriptions (if used) | 3.1.2(a): "ongoing value … at least seven days … available across all of the user's devices"; 3.1.2(c): describe clearly what the user gets | Live multi-model forecasts are continually updated data, so they fit |

### 1.10 Review timing and build requirements

- "On average, 90% of submissions are reviewed in less than 24 hours" ([App Review](https://developer.apple.com/distribute/app-review/)). Plan for a rejection round anyway.
- Since 2026-04-28, uploads must be built with Xcode 26 and the iOS 26 SDK ([upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)). The project targets iOS 26 (`ios/project.yml`).

### 1.11 Checklist: what is missing in the repo today (checked against the code)

- [ ] **Paid Apple Developer Program membership.** Today's team is a Personal Team with 7-day profiles (1.1).
- [ ] **App icon.** There is no `.xcassets` anywhere under `ios/`, and the built `DarkSky.app` has no `Assets.car` or `CFBundleIcons`. The 2026-09-27 review item 14 lists "No app icon".
- [ ] **`PrivacyInfo.xcprivacy`** for the app target (CA92.1, C617.1, E174.1, Coarse Location). The widget needs one only if it gains a covered API.
- [ ] **`ITSAppUsesNonExemptEncryption = NO`** in `ios/project.yml` info properties.
- [ ] **Privacy policy page and support page** with contact details, plus an in-app link from About.
- [ ] **Credits and licenses screen** (`docs/ios/HELP-ABOUT.md` §6). It should include Open-Meteo (CC BY 4.0) with DWD, ECMWF, NOAA and CAMS credits, USGS, AWS Terrain Tiles, MapLibre BSD-2, d3-celestial BSD-3, IAU figures (CC BY 4.0), the Bright Star Catalogue, and the SAH credit if NPF stays.
- [ ] **Hide fixture layers** (light pollution, PAD-US) and the disabled iCloud toggle in release builds, or ship real data.
- [ ] **Remove the client's direct keyless Open-Meteo fallback** for distributed builds. `ConditionsClient.race` starts `fetchDirect` against `https://api.open-meteo.com` (`SkyCore/OpenMeteoDirect.swift:60`) after a 3 s hedge (`ConditionsClient.swift:71`). That is the free, non-commercial endpoint.
- [ ] **Worker on the commercial Open-Meteo endpoint.** `FORECAST_HOST = "https://api.open-meteo.com"` (`worker/src/sources/openmeteo.ts:6`) must become `customer-api.open-meteo.com` with `&apikey=` from a Worker secret ([pricing FAQ](https://open-meteo.com/en/pricing)).
- [ ] **Turn 7Timer! off**: `"SEVENTIMER_ENABLED": "true"` in `worker/wrangler.jsonc`.
- [ ] **NPF rule**: get the Société Astronomique du Havre's consent, or replace it (2.2).
- [ ] **StoreKit 2 products and paywall**, with no upsell inside the widget, if monetized.
- [ ] **Store name** not built on a bare "Dark Sky" (1.3).
- [ ] **Field validation** before any accuracy claim in marketing: dark-site verdict, AR alignment and a real-sky stack are all "Unverified" in `docs/ios/CAPABILITIES.md`.
- [ ] Optional: remove `NSAllowsLocalNetworking` until it's used, and move the Worker to a custom domain (`docs/ios/PLAN.md` pre-deploy decision 1).

Already fine: the purpose strings, background mode plus task identifiers, iPhone-only targeting, the iOS 26 SDK, and matching app and widget versions (the built app and `DarkSkyWidgets.appex` both report 0.1.0 (1)). Debug hooks are wrapped in `#if DEBUG`.

---

## 2. Data and licence blockers for a paid or ad-supported app

`docs/data-licensing.md` already rates each source for "Distribution". The table re-checks that against today's terms and adds prices and alternatives.

| Source | Commercial use allowed? | Price at expected volume | Required attribution | If blocked |
|---|---|---|---|---|
| **Open-Meteo** forecast + air quality (HRRR, GFS, ICON, ECMWF, CAMS) | **Only with a subscription.** "Operating websites or apps that have subscriptions or display advertisements" and "integrating our service into commercial products or promotional activities" count as commercial ([terms](https://open-meteo.com/en/terms)). The free tier is also capped at 10,000 calls/day and 300,000/month ([pricing](https://open-meteo.com/en/pricing)) | Standard **$29/mo** or $319/yr for 1M calls/month; Professional **$99/mo** or $1,099/yr for 5M; above that, Professional 10M-call units priced by volume at $185 each for 1 unit, $150 each for 2, $130 each for 3, then lower; Enterprise 50M+ on request. Figures come from the Stripe pricing table embedded on [the pricing page](https://open-meteo.com/en/pricing). Air Quality is included in Standard. No per-call overage charge | CC BY 4.0: credit, a licence link and "indicate if changes were made" ([licence](https://open-meteo.com/en/licence)). Keep the DWD credit (`docs/data-licensing.md`) | Apple WeatherKit (below) or NWS `api.weather.gov` |
| **7Timer!** ASTRO | **No**: "as long as you are not using them for commercial purpose" ([doc](https://www.7timer.info/doc.php)) | — | Notification requested | Drop it: `SEVENTIMER_ENABLED=false`. The jet-stream seeing proxy from Open-Meteo already exists (ADR-0013 §2) |
| **EPA AirNow** | The Data Use Guidelines state no commercial ban. They require labelling data "preliminary", crediting the reporting agencies and AirNow, not altering forecasts, using the official AQI colors, and telling the agencies and AirNow about products that use the data ([DataUseGuidelines.pdf](https://docs.airnowapi.org/docs/DataUseGuidelines.pdf); [FAQ](https://docs.airnowapi.org/faq)) | Free key. The rate limit is per key per hour; the FAQ says "see documentation for each web service". The often-quoted 500/hour figure is **(unverified)** | As above. The Worker already carries "Preliminary data from EPA AirNow…" (`worker/src/sources/airnow.ts:8`). The iOS app doesn't show AirNow yet | Open-Meteo CAMS PM2.5 (already used) |
| **NOAA NWS / RAP-Smoke / SWPC** | Yes. NWS pages "may be used without charge for any lawful purpose". The NWS name and logo are protected ([NWS disclaimer](https://www.weather.gov/disclaimer)). `api.weather.gov` needs a User-Agent ([API docs](https://www.weather.gov/documentation/services-web-api)). No SWPC-specific terms page was found **(unverified)** | Free | Credit NOAA/NWS/SWPC. Don't use the logos or imply endorsement | — |
| **NOAA NESDIS HMS** smoke polygons | Yes as a U.S. government work. The repo records the ArcGIS item's licence as CC0 (`docs/data-licensing.md`); I did not re-fetch it today **(unverified)** | Free | Credit NOAA NESDIS HMS and the analysis time | — |
| **USGS The National Map** basemaps | Yes: "considered to be in the U.S. public domain and can be freely used without permission" ([USGS FAQ](https://www.usgs.gov/faqs/are-usgs-reportspublications-copyrighted)). No published tile rate limit was found **(unverified)** | Free | Requested wording for products sold: "Data compiled by the U.S. Geological Survey" ([Crediting USGS](https://www.usgs.gov/information-policies-and-instructions/crediting-usgs)) | — |
| **OpenFreeMap** | Commercial use is allowed ([openfreemap.org](https://openfreemap.org/)). But the ToS bars "attempt to collect data from the service in automated ways without permission" ([ToS](https://openfreemap.org/tos/)). **The iOS app doesn't use it**: `docs/data-licensing.md` rejected it on 2026-09-26 over offline packs, and `grep` finds no reference in `ios/`, `app/`, `shared/` or `config/` | Free | "OpenFreeMap © OpenMapTiles Data from OpenStreetMap" (ODbL) | Self-host its weekly planet MBTiles if vector tiles are ever wanted |
| **MapLibre Native** | Yes, BSD-2-Clause ([repo](https://github.com/maplibre/maplibre-gl-native-distribution)) | Free | Licence notice in the app's acknowledgements | — |
| **AWS Terrain Tiles** | Yes; public-domain sources | Free | Per-source lines from the [attribution file](https://github.com/tilezen/joerd/blob/master/docs/attribution.md), e.g. "3DEP … SRTM terrain data courtesy of the U.S. Geological Survey" | USGS 3DEP |
| **Star catalogs (bundled)** | Bright Star Catalogue: data.gov lists it as "U.S. Government Works" (`docs/data-licensing.md`; not re-fetched today, **unverified**). d3-celestial: BSD-3 ([LICENSE](https://github.com/ofrohn/d3-celestial/blob/master/LICENSE)). IAU figures: CC BY 4.0 (search result only, **unverified**) | Free | Hoffleit & Warren + HEASARC; the Olaf Frohn BSD notice; IAU/Sky & Telescope (Sinnott, Fienberg) | — |
| **OpenNGC** (proposed, ADR-0013) | Yes, but CC BY-SA 4.0 ([repo](https://github.com/mattiaverga/OpenNGC)). Share-alike binds the bundled data file, which must stay CC BY-SA | Free | CC BY-SA credit | Messier (public domain) only |
| **PAD-US** | Yes, as a USGS product | Free | "U.S. Geological Survey (USGS) Gap Analysis Project (GAP), 2024, PAD-US 4.1 … https://doi.org/10.5066/P96WBCHS" ([PAD-US download](https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-download)) | — (currently a fixture) |
| **Light pollution: NASA Black Marble VNP46A4** | Yes, open data. Don't imply NASA endorsement ([Earthdata data use](https://www.earthdata.nasa.gov/engage/open-data-services-software-policies/data-use-guidance)) | Free, needs an Earthdata token (`docs/credentials-setup.md`) | Cite the dataset | — (currently a fixture) |
| **Falchi 2016 atlas / lightpollutionmap.info** | Falchi is CC BY-NC (search snippet of GFZ, **unverified**), and the repo already forbids it (`tests/test_forbidden_sources.py`) | — | — | Keep excluding it |
| **NPF rule** (in-app calculator, `App/Tools/Calculators.swift:152`) | The Société Astronomique du Havre says: "No commercial use is allowed without prior consent. Any development using this formula shall give credit to the author and the SAH" ([SAH](https://sahavre.fr/wp/regle-npf-rule/)). U.S. copyright does not cover "any idea, procedure, process, system, method of operation … principle" ([17 U.S.C. §102(b)](https://www.law.cornell.edu/uscode/text/17/102)), so this is more a courtesy and reputation issue than a copyright one. That is general information, not legal advice | — | Credit Michaud and the SAH | Ask the SAH for consent (Brian's call; I contacted no one), or lead with a trail-length rule derived from pixel pitch and focal length, labelled as such |

**Alternative weather source: Apple WeatherKit.**
- 500,000 calls/month are included with the membership; then $49.99/month for 1M, $99.99 for 2M, $249.99 for 5M, $499.99 for 10M ([WeatherKit](https://developer.apple.com/weatherkit/)).
- Hourly forecasts include `cloudCoverByAltitude` (low, medium, high) on iOS 18+ ([CloudCoverByAltitude](https://developer.apple.com/documentation/weatherkit/cloudcoverbyaltitude)).
- It needs the Apple Weather mark and a legal link ([WeatherKit](https://developer.apple.com/weatherkit/)).
- The catch is that it is one blended forecast without named models or run times. That undoes ADR-0010's rule of showing model disagreement and provenance. It works as a cheap free-tier source, not as a replacement for the multi-model view.

### 2.1 Running-cost estimate

**What the code does per request:**
- A cold `/v1/conditions` makes four model requests with 12 hourly variables each (`FORECAST_VARIABLES`, `worker/src/sources/openmeteo.ts`), one HRRR 15-minute request with 5 variables, and two CAMS air-quality requests.
- Open-Meteo counts more than 10 variables as a fraction above one call ("15 weather variables … 1.5 API calls"), and its calculator counts models separately ([pricing FAQ](https://open-meteo.com/en/pricing)).
- So a cold request costs about **7.8 weighted calls**: 4 × 1.2, plus 1, plus 2. A later refresh after a new HRRR run costs about 2.2, plus about 1.2 for each slower model that has also updated.
- Caching is per 0.05° cell, window and model run (`docs/ios/PLAN.md` §Behaviour). Users in different places rarely share entries.
- Whether `meta.json` reads count as calls is **(unverified)**. They are cached for up to an hour.

**Measured:** the live Worker served 296 `/v1/conditions`, 4 `/v1/space-weather` and 1 `/health` requests from 2026-09-20 to 2026-09-27 (Workers Observability, service `dark-sky-conditions`). All of that is Brian's own testing, so it is only a ceiling for one heavy user.

**Assumptions per daily active user (DAU):**
- Two sessions a day. Each makes 5 conditions requests (Tonight, plus about 4 Week blocks of up to 48 h, per `WeekModel.blocks`) and 1 space-weather request.
- Two saved spots refreshed in the background about 4 times a day (3 h minimum interval, `SpotRefresh.swift:16`).
- That is about **20 Worker requests** and about **90 weighted Open-Meteo calls** per DAU per day. Low case: 35, one session and no spots. High case: 150.
- A month is 30 days.

| | 100 DAU | 1,000 DAU | 10,000 DAU |
|---|---|---|---|
| Worker requests / month | 60k | 600k | 6M |
| Cloudflare Workers | $0: fits the free plan's 100,000/day. The account also hosts `blaumeux`, which Brian's notes say is on Workers Paid; not re-checked in billing | $0 extra | $5/mo plan (10M requests included, then $0.30/M; subrequests not billed) ([Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)) |
| Open-Meteo weighted calls / month (central; range) | 270k (105k–450k) | 2.7M (1.05M–4.5M) | 27M (10.5M–45M) |
| Open-Meteo plan | Standard $29 | Professional $99 (the low case, 1.05M, is just over Standard's 1M) | 3 × 10M units = $390 (2 units = $300 with more cache sharing; 5 units = $575 in the high case) |
| Apple Developer Program | $8.25 ($99/yr) | $8.25 | $8.25 |
| **Total / month, every user gets live data** | **≈ $37–42** | **≈ $107–112** | **≈ $400** |
| **Total if only subscribers get live data** (10% of DAU, as an illustration, not a benchmark) | 10 subscribers → still Standard $29, because any paid app is commercial → ≈ $37 | 100 subscribers → Standard $29 → ≈ $37 | 1,000 subscribers → Professional $99 → ≈ $107 |

Space-weather KV reads stay inside the included 10M/month ([Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)). One thing to watch: AirNow's hourly per-key limit at 10,000 DAU, because each distinct cell needs its own hourly observation.

---

## 3. Ways to make money

### 3.1 Apple's cut and the 2026 rules

- **Small Business Program:** 15% commission for developers with up to $1M in proceeds in the prior year, and for new developers. Enroll after accepting the Paid Apps Agreement ([SBP](https://developer.apple.com/app-store/small-business-program/)). The standard rate is 30%. Subscriptions drop to 15% after a year of paid service, and SBP members pay 15% throughout ([Subscriptions](https://developer.apple.com/app-store/subscriptions/)).
- **US external purchase links:** Guideline 3.1.1(a) now says the link entitlements "are not required for developers to include buttons, external links, or other calls to action in their United States storefront apps", and the anti-steering ban applies "except for the United States storefront" ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)). On 2025-12-11 the Ninth Circuit largely upheld the contempt finding. It also said Apple may charge a commission on linked-out purchases limited to what is "genuinely and reasonably necessary" ([opinion PDF](https://cdn.ca9.uscourts.gov/datastore/opinions/2025/12/11/25-2935.pdf); summary by [Fenwick](https://www.fenwick.com/insights/publications/ninth-circuit-largely-upholds-ruling-in-epic-v-apple)). Reports say the case is now before the Supreme Court as No. 25-1311 ([AppleInsider](https://appleinsider.com/articles/26/04/06/epic-vs-apple-lawsuit-over-app-store-fees-is-moving-to-the-supreme-court-again), search snippet, **unverified**). For a small developer, a web checkout saves little over 15% and adds tax, refund and support work.
- **EU, from 2026-10-01:** one set of terms. IAP is 26%, or 15% for SBP members and for subscriptions after year one. Alternative payment processing is 20%, or 10%. Link-outs are 15%, or 10%. Apps distributed outside the App Store pay a 5% Core Technology Commission. The initial acquisition fee and store services fee are gone ([Apple Newsroom, Aug 2026](https://www.apple.com/newsroom/2026/08/apple-announces-changes-for-apps-in-the-european-union/)).
- **Physical goods and services:** Dust & Starlight workshops and prints are "physical goods or services that will be consumed outside of the app", so they must be sold with Apple Pay or a card, not IAP (3.1.3(e), [Guidelines](https://developer.apple.com/app-store/review/guidelines/)). No commission applies to those sales.
- **Tips:** "Apps may use in-app purchase currencies to enable customers to 'tip' the developer" (3.1.1). Donations are only for approved nonprofits (3.2.1(vi)) ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
- **Family Sharing:** available for non-consumables and subscriptions. "Once you turn on Family Sharing for an In-App Purchases in App Store Connect, you can't turn it off" ([Turn on Family Sharing](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases)).
- **Introductory offers:** free trial, pay as you go, or pay up front, one per subscription group. Promotional offers and offer codes also exist ([Subscriptions](https://developer.apple.com/app-store/subscriptions/)).
- **Prices:** 900 price points from $0.29, with automatic equalization across storefronts ([news qzex35ch](https://developer.apple.com/news/?id=qzex35ch)).

### 3.2 What competitors charge today (US App Store)

Prices come from each app's US listing. The rows for DarkScout, Astrospheric and Clear Outside were re-read by me; the rest come from a delegated fetch.

| App | Price | Model | Headline features | Link |
|---|---|---|---|---|
| **DarkScout** (closest direct rival) | Free | Subscription: PRO **$39.99/yr**, **$5.99/mo** | "Astro Score", clear-sky forecast, moonlight, Milky Way timing, saved spots, clear-night alerts, horizon profile | [id6760223860](https://apps.apple.com/us/app/darkscout-astro-planner/id6760223860) |
| PhotoPills | **$10.99** | Paid, no IAP | Sun, Moon and Milky Way planner, AR, exposure calculators | [id596026805](https://apps.apple.com/us/app/photopills/id596026805) |
| PlanIt Pro | **$9.99** | Paid + IAP: 3D model $0.99/mo or $5.99/yr; Location Explorer $4.99/mo or $29.99/yr | Landscape and night planner, VR/AR finder | [id898876435](https://apps.apple.com/us/app/planit-pro-photo-planner/id898876435) |
| The Photographer's Ephemeris | **$9.99** | Paid + IAP: Skyfire $9.99 per 3 months; Skyfire Plus $12.99 per 3 months | Map-based sun, moon and Milky Way; sky-glow forecast add-on | [id366195670](https://apps.apple.com/us/app/the-photographers-ephemeris/id366195670) |
| TPE 3D | **$11.99** | Paid | 3D terrain light simulation | [id1152829925](https://apps.apple.com/us/app/photographers-ephemeris-3d/id1152829925) |
| Clear Outside | Free | Free | Hourly low, mid and high cloud; this looks like a new listing with 9 ratings | [id6755946435](https://apps.apple.com/us/app/clear-outside/id6755946435) |
| Astrospheric | Free | Pro subscription $2.99 and $29.99 (periods not labelled; probably monthly and yearly, **unverified**) | Astronomy weather: clouds, seeing, transparency, smoke, aurora | [id1166046863](https://apps.apple.com/us/app/astrospheric/id1166046863) |
| SkySafari 7 Pro | **$17.99** | Paid + Premium $39.99 or $4.99/mo | Planetarium, telescope control | [id1567658979](https://apps.apple.com/us/app/skysafari-7-pro/id1567658979) |
| Stellarium Mobile | Free | PLUS $1.99 or $18.99 (periods **unverified**) | Star map, AR, satellites | [id1458716890](https://apps.apple.com/us/app/stellarium-mobile-star-map/id1458716890) |
| Sky Guide | Free | PLUS $4.99/mo or $39.99/yr; PRO $8.99/mo, $59.99/yr or $249.99 lifetime | AR star identification, alerts | [id576588894](https://apps.apple.com/us/app/sky-guide/id576588894) |
| NightCap Camera | **$2.99** | Paid | Long exposure, star-trail and meteor modes | [id754105884](https://apps.apple.com/us/app/nightcap-camera/id754105884) |
| Spectre Camera | Free | Pro $4.99 one-time | "AI-powered" long exposure | [id1450074595](https://apps.apple.com/us/app/spectre-camera/id1450074595) |
| Slow Shutter Cam | **$2.99** | Paid | Low-light accumulation, light trails | [id357404131](https://apps.apple.com/us/app/slow-shutter-cam/id357404131) |
| Halide Mark III | Free | IAP $9.99, $19.99 (periods **unverified**), $69.99 one-time | Pro RAW camera, "Process Zero"; no astro mode confirmed | [id885697368](https://apps.apple.com/us/app/halide-mark-iii-pro-camera/id885697368) |

### 3.3 What would be different about Dark Sky

1. **One headline number.** Moon-free astronomical darkness above the real terrain horizon at a given spot. The measured Candlestick Camp profile agrees within 0.494° RMS (`docs/ios/PLAN.md` §Log).
2. **Forecast trust made visible.** Four named models side by side, with run times, smoke (RAP-Smoke, HMS) and the source and age of every number (ADR-0006, ADR-0010). DarkScout and Astrospheric give a score or a forecast. The repo's own survey found no competitor that joins terrain horizon, multi-model trust, gear and Moon avoidance (`docs/deepsky/research/apps.md` §5).
3. **Planning, verdict and iPhone capture in one app.** The stacking is deterministic and keeps the originals, with no generative AI (ADR-0011 as amended). Spectre markets "AI-powered" long exposure.
4. **Privacy by design.** No accounts, coordinates rounded to about 5 km, spots kept on the phone.
5. **An honest scope.** It gives the land manager, "never 'you may camp here'" (README). That fits Brian's understated public voice.

Until the dark-site checks in `CAPABILITIES.md` are done, points 1–3 are design claims, not proven accuracy. Marketing copy should wait for them.

### 3.4 Models compared

Proceeds are after the 15% SBP commission. "Data cost" uses section 2.1.

| Model | Fits Apple rules | Data-cost fit | Break-even at 1,000 DAU | Fit with Brian |
|---|---|---|---|---|
| Free, no money, no promotion | Yes | Poor. Open-Meteo's free tier is non-commercial and capped at 10k calls/day, about 110 DAU on my assumptions. Past that it needs the paid key with no income | Never | Fine as a hobby, but it can't grow |
| Paid upfront (e.g. $9.99 → $8.49) | Yes | Mismatched: cost recurs, revenue doesn't | ≈ 13 new sales every month just to cover ≈ $110/mo | Simple, no paywall; matches PhotoPills and TPE |
| Freemium, one-time IAP unlock | Yes (3.1.1) | Same mismatch as paid upfront | Same | Needs StoreKit and a free tier |
| **Freemium + subscription for live conditions** (e.g. $19.99/yr → $16.99, about $1.42/mo per subscriber) | Yes; live data is "ongoing value" (3.1.2(a)) | **Good.** Only subscribers call the paid APIs, so cost follows revenue | ≈ 26 subscribers at $37/mo; ≈ 76 at $107/mo | Understated: the core planner stays free |
| Tip jar (consumable IAP) | Yes (3.1.1) | Poor: the app is still commercial, so it needs the paid key, and income is unpredictable | Unknown | Low pressure, but can't carry fixed costs |
| Free app that supports Dust & Starlight (links to workshops and prints) | Yes; workshops sold outside IAP (3.1.3(e)) | Open-Meteo counts "promotional activities" as commercial ([terms](https://open-meteo.com/en/terms)), so it still needs the paid key | Depends on workshop sales, not app metrics | Good brand fit, but data cost stays |

### 3.5 Recommendation

**Recommended: a free app plus one auto-renewing "live conditions" subscription.**
- Free, with zero marginal cost because it runs on the device: Tonight's darkness, Moon and Galactic Center; the Sky view; tools; capture and stacking; the map and offline areas.
- Subscription: multi-model clouds, smoke, the Week verdicts, spot alerts and the verdict widget.
- Suggested prices: $19.99 a year, a monthly option around $2.49, and a one-week free trial as an introductory offer. That is half of DarkScout ($39.99/yr, $5.99/mo) and below Sky Guide PLUS ($39.99/yr).
- Turn Family Sharing on. That is irreversible, so decide once.

Why this model:
1. Data cost follows paying users: about $37 a month covers up to about 370 subscribers on Open-Meteo Standard (2.7k calls × 370 ≈ 1M).
2. It meets 3.1.2(a) naturally.
3. It needs no ads or tracking, so the privacy label stays clean.
4. The free app can link to Dust & Starlight workshops (3.1.3(e)), because the free tier doesn't call Open-Meteo.

A free-tier cloud line could come from NWS `api.weather.gov` directly on the device. That is public domain and has no cost to Brian ([NWS API](https://www.weather.gov/documentation/services-web-api)), but it is one total sky-cover value with no layers. Whether it carries layer detail is **(unverified)**.

**Expected monthly cost at 1,000 DAU:**
- If about 10% subscribe (an illustration, not a benchmark): **≈ $37** (Open-Meteo Standard $29 + Apple $8.25 + Workers $0).
- If every DAU were a subscriber: **≈ $112**.

**Fallback: paid upfront at $9.99, with live conditions for everyone.** It is simpler, with no StoreKit subscription work and no paywall, and it sits at the same price as PlanIt Pro and TPE. The risk is that data cost keeps growing with the installed base: about $110 a month at 1,000 DAU needs about 13 new sales a month. Set a Worker budget alarm and keep WeatherKit (500k calls/month included) ready as a degraded source if sales stall.

---

## 4. Business basics (general information, not legal or tax advice)

**Sole proprietor vs LLC**
- A sole proprietorship needs no state formation filing. There is no liability separation between business and personal assets ([SBA: choose a business structure](https://www.sba.gov/business-guide/launch-your-business/choose-business-structure), search summary). Income goes on Schedule C ([IRS Schedule C instructions](https://www.irs.gov/instructions/i1040sc), search summary).
- Utah fees, from the Division of Corporations fee schedule ([currentfees.pdf](https://commerce.utah.gov/wp-content/uploads/2023/04/currentfees.pdf); [DBA page](https://commerce.utah.gov/corporations/business-entities/dba/)): DBA registration $22, DBA renewal $18; LLC certificate of organization $59, LLC annual renewal $18, late fee $10.
- A single-member LLC that is a disregarded entity can report on the owner's SSN unless it has employees or excise-tax liability ([IRS single-member LLCs](https://www.irs.gov/businesses/small-businesses-self-employed/single-member-limited-liability-companies)).
- Apple shows an LLC as seller only after organization enrollment with a D-U-N-S number and website (1.2).
- Where to confirm: [Utah OneStop Business Registration](https://businessregistration.utah.gov/), the [Utah Division of Corporations](https://commerce.utah.gov/corporations/), and a Utah CPA or attorney.

**Millcreek license.** Millcreek requires a city business license, including a "Home Business" category. The application needs a state sales tax ID "if selling products" ([Millcreek business licensing](https://www.millcreekut.gov/457/Business-Licensing)). Whether an app sold through Apple counts is for the city to say. The existing Dust & Starlight business may already hold a license. I didn't check.

**Sales tax and VAT**
- Apple's tax service computes tax "in countries or regions where taxes are administered" ([Set a tax category](https://developer.apple.com/help/app-store-connect/manage-app-information/set-a-tax-category/)). A monthly transaction tax report covers US and Canadian sales, use and similar taxes ([Transaction tax report](https://developer.apple.com/help/app-store-connect/reference/reporting/transaction-tax-report-fields/)).
- Utah makes marketplace facilitators, including for "products transferred electronically", over $100,000 in Utah sales, collect and remit the tax ([Utah Tax Commission](https://tax.utah.gov/business/sales-tax/other-sales-tax/marketplace-facilitators/)).
- That Apple is the facilitator for App Store sales into Utah is my inference from those two pages, **(unverified)** as a named statement.

**App Store Connect money setup**
- Sign the Paid Apps Agreement, submit a W-9 and add a bank account ([tax info](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/); [banking](https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information/)). Payment is "within 45 days of the last day of the fiscal month" ([receiving payments](https://developer.apple.com/help/app-store-connect/getting-paid/overview-of-receiving-payments)). The minimum threshold for a US bank in USD is $0.02 ([threshold](https://developer.apple.com/help/app-store-connect/reference/reporting/minimum-payment-threshold)).
- Then enroll in the Small Business Program.

**Support obligations**
- Guideline 1.5: the app and its Support URL must "include an easy way to contact you" ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)). The Support URL must show contact details "as may be required by local law" (1.3).
- Review replies are optional ([respond to reviews](https://developer.apple.com/help/app-store-connect/monitor-ratings-and-reviews/respond-to-reviews), search summary). Apple handles refunds **(unverified on a primary page today)**.
- A small support page on the Dust & Starlight site with an email address and a P.O. box covers both requirements.

**Minimum privacy policy for an app with no accounts.** Guideline 5.1.1(i) requires it in App Store Connect and inside the app. It must cover what is collected, how, all uses, third parties, retention and deletion, and how to revoke consent ([Guidelines](https://developer.apple.com/app-store/review/guidelines/)). For Dark Sky:
1. No accounts, ads, analytics or tracking.
2. Precise location stays on the phone. A cell rounded to 0.05° (about 5 km) goes to the Dark Sky conditions service on Cloudflare to fetch forecasts. Say what is logged and for how long, after checking Workers Logs.
3. Map tiles load directly from USGS and AWS, and those servers see your IP and the area viewed.
4. Spots, captures and settings stay on the device and in your own photo library. Deleting the app deletes them.
5. Camera, motion and photo access are used only for the features named in the permission prompts.
6. Purchases are handled by Apple.
7. A contact email and an effective date.

---

## 5. A realistic sequence, with a provable checkpoint for each step

| # | Step | Checkpoint (provable) |
|---|---|---|
| 1 | Decide seller identity (individual now, or LLC first) and the store name | Decision recorded with `/decision-log` or an ADR. Name reserved when the App Store Connect record is created (step 3) |
| 2 | Enroll in the Apple Developer Program ($99) | `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` shows a team with `isFreeProvisioningTeam = 0`, and `security find-identity -v -p codesigning` lists an `Apple Distribution` identity |
| 3 | Register App IDs and App Group; create the App Store Connect record | App Store Connect lists the app with bundle ID `…darksky`; the Identifiers page shows `…darksky.widgets` with App Groups |
| 4 | Store hygiene in the repo: icon, `PrivacyInfo.xcprivacy`, `ITSAppUsesNonExemptEncryption=NO`, remove `NSAllowsLocalNetworking`, hide fixtures and the dead toggle in Release | Release build: `DarkSky.app` contains `Assets.car` and `PrivacyInfo.xcprivacy`; `plutil -p Info.plist` shows `ITSAppUsesNonExemptEncryption => false`; Xcode's privacy report (Organizer › Generate Privacy Report) lists CA92.1, C617.1 and E174.1 |
| 5 | Licences: subscribe to Open-Meteo Standard; add the key as a Worker secret; switch to `customer-api.open-meteo.com`; set `SEVENTIMER_ENABLED=false`; remove or gate the client's direct fallback; settle NPF | `/health` shows 7Timer disabled and the Open-Meteo customer endpoint healthy (the Worker needs a small change to report its endpoint or key presence, never the key). `grep -r "api.open-meteo.com" ios/` finds nothing in Release code paths. `docs/data-licensing.md` "Distribution" column updated |
| 6 | Privacy policy, support page and credits screen | Both URLs return 200 from the D&S site; the in-app About links open them; the Credits screen lists every row of `docs/data-licensing.md` in use |
| 7 | Upload build 1; internal TestFlight (Brian plus a few friends as App Store Connect users) | "TestFlight build 1 (0.1.0) processed and available to internal testers" in App Store Connect |
| 8 | Field validation at a dark site (the `CAPABILITIES.md` rows for the verdict, AR and capture) | New §Log entries in `docs/ios/PLAN.md`, and `CAPABILITIES.md` "Field-tested" cells change from "Unverified" to dated entries |
| 9 | External TestFlight (public link, small group) | "Beta App Review approved" for the first external build |
| 10 | StoreKit 2: subscription group, one-week intro offer, Family Sharing on, paywall outside the widget; Paid Apps Agreement, W-9, bank, Small Business Program | App Store Connect shows the Paid Apps Agreement "Active", the SBP enrollment confirmed, and the subscription "Ready to Submit". A StoreKit configuration-file test passes purchase and restore in the simulator |
| 11 | Store listing: 6.9″ screenshots (from `testScreenshotTour`), description, keywords, age rating (expect 4+), privacy label (Coarse Location, not linked), content rights, DSA trader status with a P.O. box | App Store Connect version page has no missing-field warnings |
| 12 | Submit v1.0 | "Ready for Distribution" status |
| 13 | After launch: watch cost and load | Workers Observability request counts and Open-Meteo's 80%/90% usage emails ([pricing FAQ](https://open-meteo.com/en/pricing)) compared with 2.1. Upgrade the plan before 100% |

---

## Claims I could not verify

- Whether paid individual enrollment keeps team ID `25P35HU7ZH`, and whether `com.brianbusch.darksky` stays registrable after moving from the Personal Team.
- QA1915 and Apple's encryption-export pages (read only as search snippets); the exact wording of the App Store Connect content-rights question; the Icon Composer workflow details.
- Apple's "DARK SKY" trademark record and DarkSky International's registration (USPTO pages returned 403).
- Supreme Court docket No. 25-1311 and its schedule (secondary source only). The Ninth Circuit holding was read through Fenwick's summary because the court PDF didn't parse.
- Whether Open-Meteo counts `meta.json` reads as API calls, and how its calculator weights models exactly (the page's calculator lists "Models" as a factor).
- The AirNow per-key hourly limit figure (500/hour); SWPC-specific terms; HMS's CC0 item licence (repo record only); USGS tile-service rate limits.
- The Bright Star Catalogue's data.gov licence and the IAU figures' CC BY 4.0 (repo records and search only); Falchi's CC BY-NC (search snippet).
- NWS `skyCover` having no layer breakdown.
- Astrospheric, Stellarium and Halide IAP billing periods.
- Whether Workers Logs keeps request URLs or IPs for this Worker (so whether "Data Not Collected" is defensible).
- That Brian's Cloudflare account is on Workers Paid (from his notes, not billing).
- That Apple is Utah's marketplace facilitator for App Store sales (inference).
- That Apple handles refunds, and the review-reply details (not re-read on a primary page).
- That `NSMotionUsageDescription` is optional for this app's Core Motion use.
- All per-user request rates in 2.1. They are assumptions, to be replaced with Workers Observability data from TestFlight users.
