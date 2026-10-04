# GTL iOS development roadmap

Status: product plan after 1.0.1 (build 33), written 4 October 2026. Source: the roadmap of the Android GTL (2.0.19), filtered for this iOS app.

This is not a code spec. It records what is worth building next, in what order, and why. Before a wave is implemented, it needs its own brief and test list.

Effort: calendar days for one developer who knows this codebase.

Related: [README-en.md](README-en.md), [gtl-ios-decline-fix-plan-hu.md](gtl-ios-decline-fix-plan-hu.md), [gtl-ios-possible-decline-hu.md](gtl-ios-possible-decline-hu.md).

## Selection rule

An item is on this list only if it can be added **without breaking or blocking what works today**. Concretely, every item must keep these intact:

- **Recording contract.** Start only from the foreground, While Using the App plus Precise Location, `CLBackgroundActivitySession` while recording, blue indicator until Stop. No Always request, no background start.
- **Privacy.** The track stays on the phone. Nothing stored is sent to the developer or a third party. The App Store label stays Data Not Collected.
- **Stored data.** Existing tracks keep opening and exporting. A database change is additive (new columns or tables with defaults), never a rewrite of `gps_events`.
- **Store standing.** No new permission, background mode, or hidden feature that would reopen the review questions answered for 1.0.1.

Nothing here should ship before 1.0.1 is approved. Each wave is a separate update.

## Already on iOS (from the Android list)

These Android items are done in the iOS app and are not repeated below:

- Map HUD with large speed, accuracy, and, while logging, distance, elapsed time, and REC
- Speed-colored track by usage band, with the legend (open or collapsed dots)
- **Heading-up following with gating** (Android item 3): course above 1 m/s, compass below, 5 degree steps, about 52 degree pitch, two-finger tilt kept, north dial restores; Keep whole track on screen stays north-up
- Saved-track cards with thumbnail, distance, time, average and top speed
- GPX 1.1 and KMZ with absolute GPS altitude and Start / Pause / Stop placemarks
- Elevation profile with a dashed barometric line, QNH, GPS altitude choice
- OSM (Mapsforge, drawn with MapLibre) and Turistautak offline maps, with file checks
- Apple Maps standard, satellite, and hybrid with realistic elevation
- System light and dark theme for the app UI; Apple Maps follows dark mode on its own

## Not applicable or rejected on iOS

| Idea | Why not |
| --- | --- |
| GNSS skyplot, constellation list, SNR | iOS has no public API for satellites. Not buildable. |
| Live sharing, own server, upload | Against the privacy promise and the Data Not Collected label. |
| Snapping to streets (map matching) | Against the point of the app: the line is what the chip recorded. |
| Community, kudos, segments | A different product. |
| Apple Watch app | Weeks of work, a separate target and test matrix. Later, if ever. |
| GPX import | The app is a logger, not an archive manager. |
| FIT / TCX export | Only if someone asks for Garmin Connect. |
| Turn-by-turn navigation | Driver distraction and review risk; Apple Maps does it. |
| Temperature-colored track | iPhones have no ambient temperature sensor. |
| Landscape tank HUD | The app is portrait-only with `UIRequiresFullScreen`. Allowing landscape changes every screen and the follow camera, which is exactly the "do not break" risk. Revisit only as a separate, isolated full-screen view if riders ask. |
| Recording that starts by itself (boot, geofence, background) | Needs Always and breaks the recording contract. |

---

## Priority list

Ordered by value: what you see on every recording first, what you look at once after a trip last. Where two items are close, the cheaper one comes first in its wave.

### 1. Stationary speed shows 0 on the HUD

Value: high — the instrument shows movement while standing still · Effort: about 1 day · Wave 1

**Why.** The HUD rounds the raw `CLLocation.speed` (`model.speedMps` → `Units.hudSpeedNumber` in `gtl/UI/MapViews.swift`). Indoors, with a still phone, Doppler noise shows a few km/h. A fixed km/h threshold would cut slow walking and let a larger indoor spike through.

**What to build.** One pure engine function used by the HUD, the Route tab's live speed, and the Live Activity (item 3):

- No speed (`speed < 0`): show "—".
- `speedAccuracy` available (`CLLocation.speedAccuracy >= 0`): if speed ≤ its accuracy, show 0.
- Otherwise: if the move since the previous fix ≤ horizontal accuracy, show 0.
- Hysteresis: two significant samples to leave 0, two to return.

`RecordedFix` gets a `speedAccuracy` field (additive). The stored track is unchanged; this is a display rule only.

**Why it does not break anything.** Display only; the recording chain, filters, and stored points stay as they are.

**Test.** Engine tests for each branch and the hysteresis. Simulator: still location shows 0; a simulated route shows the speed with no 0/5 flicker.

**Permissions and declarations.** No new permission or declaration. `speedAccuracy` is part of the `CLLocation` delivered under the existing location permission.

### 2. Dark offline map and in-app theme choice

Value: high — night riding, brand, the store screenshots are dark · Effort: 2–3 days · Wave 1

**Why.** The app UI and Apple Maps already go dark with the system. The offline OSM and Turistautak maps do not: `gtl/offline-style.json` and the layer colors are a light style (background `#f3efe4`). At night a downloaded map is a white rectangle, and the light speed bands wash out.

**What to build.**

- Setting: System / Light / Dark (stored in `SettingsStore`, applied with `.preferredColorScheme` in `RootView`; System stays the default).
- A dark variant of the offline style (background, land cover, roads, water, labels) for both OSM and Turistautak, chosen from the effective color scheme.
- Contrast check on a dark map: HUD, speed bands, accuracy circle, fix cloud, S/E markers. Adjust a band only if it disappears.

**Not.** A third "high contrast" palette.

**Why it does not break anything.** The light style stays the default in light mode; the dark style is a second asset chosen at render time.

**Test.** System / Light / Dark × Apple Maps / OSM / Turistautak; HUD, speed bands, and the fix cloud readable on each.

**Permissions and declarations.** No new permission or declaration. The theme choice goes into `UserDefaults`, which the privacy manifest already declares (`CA92.1`).

### 3. Live Activity on the lock screen and Dynamic Island

Value: medium–high — a second HUD while the phone is in a pocket or on the tank · Effort: 2–3 days · Wave 1

**Why.** The iOS counterpart of the Android live notification. Speed, distance, and elapsed time on the lock screen and in the Dynamic Island while recording, plus a Stop button.

**What to build.**

- A Widget Extension target with an `ActivityAttributes` type; `NSSupportsLiveActivities` in the app's Info.plist.
- Started in `beginSession`, updated on accepted points at most every few seconds (ActivityKit has an update budget), ended in `stopLogging`.
- Stop button through an App Intent that calls the same stop path as the app button.
- Speed uses item 1's gated value.

**Why it does not break anything.** ActivityKit needs no location permission and no new background mode. The activity only displays numbers; recording still starts only from the app. If the user turns Live Activities off, nothing else changes.

**Test.** Start, lock, the activity updates; Stop from the activity ends the session the same way as the app button; force quit ends the activity.

**Permissions and declarations.** No user permission prompt, but several declarations:

- `NSSupportsLiveActivities` = `YES` in the app's Info.plist. `NSSupportsLiveActivitiesFrequentUpdates` is not needed; updates every few seconds are enough.
- A new Widget Extension target with its own bundle ID (for example `com.lkovari.mobile.apps.gtl.LiveActivity`). With automatic signing Xcode registers it and creates a provisioning profile; a new App ID appears on the developer portal.
- The extension needs its own `PrivacyInfo.xcprivacy` if it uses a required-reason API (for example `UserDefaults`); otherwise not.
- No App Group, because the data travels in the ActivityKit content. No push-token updates, so no Push Notifications capability.
- The Stop button's App Intent (`LiveActivityIntent`) needs no Info.plist key.
- App Store Connect: the privacy label does not change. One sentence in the review notes: while recording, the Live Activity shows speed, distance, and time, with a Stop button.

### 4. Lean band for motorcycle tracks (kinematic lean)

Value: high for the motorcycle default · Effort: 3–4 days · Wave 2

**Why.** Every point stores a lean angle, but the UI shows nothing of it. The current source also misleads in a corner: `BikeLeanAngle.fromGravity` uses the gravity vector, and in a steady, coordinated corner the apparent gravity falls into the bike's plane, so a phone on the tank reads close to 0°.

**What to build.**

- Engine: lean ≈ atan(v · ω / g), with v the speed and ω the turn rate. On a saved track ω comes from the change of the stored bearing over time, so it works backwards on every existing motorcycle track and does not depend on how the phone is mounted. Live: ω from the gyroscope yaw rate (Core Motion), if present.
- No band below about 3 m/s or with sparse points (bearing noise dominates).
- Drawing on Apple Maps and MapLibre: a band beside the line, or a color choice (speed / lean), left and right in separate tones; legend in degrees.
- Saved card: max left / max right.
- Hidden for Run/Hike; optional for bicycle.

**Not at first.** Drawing the gravity-based lean. A mount calibration wizard.

**Why it does not break anything.** Computed from data already stored; the stored `leanAngle` column stays as it is.

**Test.** Engine: a synthetic arc at a given speed gives the known lean; straight ~0°; standing: no band. A real hairpin track: left/right sign correct.

**Permissions and declarations.** No new permission. Live lean uses the gyroscope yaw rate from `CMMotionManager` device motion, which the app already reads under the existing `NSMotionUsageDescription`. The current text ("reads motion … to store lean angle") covers it; no rewrite needed.

### 5. Comet tail on the live track

Value: medium — cheap, adds motion while riding · Effort: about 1 day · Wave 2

**Why.** While logging, the last minute is thicker and full color, older line is quieter. It sits on the existing speed-colored runs; no new data.

**What to build.** Speed runs get an age step (2–3 steps are enough, not a per-metre gradient). Width and opacity follow the step. Only for a live session; a saved track stays even. Watch the polyline count on Apple Maps and the line layer count on MapLibre; the locked-screen rule (the map is not redrawn while the scene is inactive) stays.

**Test.** While logging, the newest part is emphasized; a saved track is unchanged; no extra redraws while locked.

**Permissions and declarations.** No new permission or declaration.

### 6. Fly along the track in Google Earth (KMZ gx:Tour)

Value: medium — strong visual, cheap, for the KMZ audience · Effort: 1–2 days · Wave 3

**Why.** The KMZ already places the line at the stored GPS altitude. A `gx:Tour` flies the Google Earth camera along it. Most of a "flyover" for a fraction of the cost.

**What to build.** In the KMZ exporter (`gtl/Engine/EngineExport.swift`): `gx:Tour` / `gx:Playlist` with `gx:FlyTo` steps on a thinned path (heading from the path, fixed tilt, range by speed). Optional switch in the share step. Engine tests on the generated KML.

**Why it does not break anything.** An extra element in the file; viewers that do not know `gx:Tour` skip it, and the existing line and placemarks are unchanged.

**Permissions and declarations.** No new permission or declaration. The file leaves through the existing share sheet, like the KMZ today.

### 7. Saved tracks: a name and stored statistics

Value: medium · Effort: 1–2 days · Wave 3

**What to build.**

- Optional name per session. Empty means the date, as today. The KMZ/GPX file name and `<name>` use it, with unsafe characters replaced.
- `track_sessions` gets `name`, `avg_speed`, `max_speed` (and `max_lean_left` / `max_lean_right` once item 4 exists), computed at Stop. The list reads them; old sessions without values keep computing from points.
- Database versioning: the first migration introduces `PRAGMA user_version` and adds columns with `ALTER TABLE … ADD COLUMN` and defaults. No table rewrite.

**Why it does not break anything.** Columns are additive with defaults; every existing session opens and exports as before.

**Test.** Upgrade from a 1.0.1 database with tracks; all open, export, and show stats; a renamed track exports under its name.

**Permissions and declarations.** No new permission or declaration. The database stays on the phone; the privacy label and the privacy manifest do not change.

### 8. Track postcard share

Value: medium — a social eye-catcher without a server · Effort: 2–3 days · Wave 3

**Why.** A dark card with the glowing speed-colored line, distance, time, an elevation strip, and a GTL stamp, as a PNG on the share sheet. No upload.

**What to build.** Draw the line on a dark canvas without map tiles (the saved-track thumbnail drawing is largely reusable), render with SwiftUI `ImageRenderer`, share through the existing share sheet.

**Why it does not break anything.** A new export option next to GPX and KMZ; nothing leaves the phone unless the user shares it, the same as GPX today.

**Permissions and declarations.** **New Info.plist key required: `NSPhotoLibraryAddUsageDescription`.** The share sheet shows a Save Image row, and without the key the app crashes when it is tapped. English and Hungarian text in `InfoPlist.xcstrings`, for example: "GTL saves the track postcard to your photo library when you choose Save Image." / "A GTL a Kép mentése választásakor a fotókönyvtáradba menti az útvonal-képeslapot." This is add-only access and cannot read the library. The privacy label does not change, because the image does not reach the developer. One sentence in the privacy policy: the postcard goes to Photos or a share target only when the user asks.

### 9. Corner gallery

Value: medium for motorcycle · Effort: 2–3 days · Wave 3

**Why.** "Left 38°, 72 km/h": the strongest corners of a saved track from bearing change and lean; a tap moves the map there. Worth it after item 4, which provides the same calculation.

**Permissions and declarations.** No new permission or declaration.

### 10. Manual pause and laps

Value: medium · Effort: 2–3 days · Wave 4

**Why.** Pause is a speed threshold today. At a fuel stop you cannot pause without Stop, which starts a new session.

**What to build.** Pause / Resume while logging; no MOVE points while paused; Resume does not create a new session. KMZ uses the existing pause icon; GPX gets a new `trkseg` at the pause. Laps afterwards.

**Careful.** The background session must stay alive while paused, or recording would need a new foreground start. Keep `CLBackgroundActivitySession` and location updates running during pause and only drop points; test on a locked phone.

**Permissions and declarations.** No new permission or declaration. The background mode stays the existing `location`; the same session runs during the pause.

### 11. Replay on the map

Value: medium — a strong video, but watched once after a trip · Effort: 5–8 days · Wave 4

**Why.** A saved track draws itself, the position marker travels along it, the HUD shows that point's numbers. Good for a store preview video.

**Expensive because:** a scrubber, speeds (1× / 10× / 60×), the marker, and the camera on both map engines. Item 6 gives most of the visual cheaper; build this only if users ask for it inside the app. Runs only on a saved track, never during a recording.

**Permissions and declarations.** No new permission or declaration.

### 12. Start and Stop from Control Center and Shortcuts

Value: low–medium · Effort: about 1 day · Wave: any time

**Why.** The iOS counterpart of the Android Quick Settings tile. Start with gloves from Control Center (iOS 18+ control) or a Shortcut / Siri phrase (App Intents, iOS 17).

**Rule that keeps the contract.** The Start intent opens the app (`openAppWhenRun`) and runs the normal Start path in the foreground, so the When In Use and precise-location checks and the alerts apply unchanged. Stop may run without opening the app.

**Permissions and declarations.** No user permission prompt.

- App Intents and App Shortcuts (Shortcuts, Siri phrase): no Siri capability and no Info.plist key; those are needed only for the old SiriKit intents.
- The Control Center control (iOS 18 `ControlWidget`) lives in a widget extension. If item 3's extension exists, it goes there; otherwise a new target and bundle ID, as in item 3.
- App Store Connect: nothing to do.

### 13. Two tracks on one map

Value: low — archive use · Effort: 2–3 days · Later

**Why.** Two selected saved tracks on one map in different colors. Read-only; the live map is unchanged.

**Permissions and declarations.** No new permission or declaration.

### 14. Elevation sculpture

Value: low · Effort: 3–5 days · Later

**Why this far back.** Apple Maps already shows realistic elevation, the KMZ hands absolute altitude to Google Earth, and item 6 adds a flight. An in-app 2.5D drawing only adds something for mountain and flight use.

**Permissions and declarations.** No new permission or declaration.

---

## Release waves

Version numbers are suggestions.

### Wave 1 — "see it at night, read it in the pocket" (1.1, about 5–7 days)

| # | Item | Effort |
| --- | --- | --- |
| 1 | Stationary speed 0 on the HUD | about 1 day |
| 2 | Dark offline map + System / Light / Dark | 2–3 days |
| 3 | Live Activity | 2–3 days |
| — | New screenshot: dark HUD map while logging | 0.5 day |

Done when: the offline map is dark in dark mode (OSM and Turistautak); a still indoor fix shows 0 km/h; the Live Activity shows the same number as the HUD; the store has a dark HUD screenshot.

### Wave 2 — "the map rides with you" (1.2, about 4–5 days)

| # | Item | Effort |
| --- | --- | --- |
| 4 | Lean band (kinematic) | 3–4 days |
| 5 | Comet tail | about 1 day |

Done when: a saved hairpin track shows left/right lean, old tracks included; while logging the last minute is emphasized; nothing extra is drawn while locked.

### Wave 3 — "the archive tells a story" (1.3, about 6–10 days)

| # | Item | Effort |
| --- | --- | --- |
| 6 | KMZ gx:Tour | 1–2 days |
| 7 | Track name + stored statistics | 1–2 days |
| 8 | Postcard PNG | 2–3 days |
| 9 | Corner gallery | 2–3 days |

### Wave 4 — deepening (later, piece by piece)

| # | Item | Effort |
| --- | --- | --- |
| 10 | Manual pause / laps | 2–3 days |
| 11 | Replay on the map | 5–8 days |
| 12 | Control Center / Shortcuts | about 1 day |
| 13 | Two tracks on one map | 2–3 days |
| 14 | Elevation sculpture | 3–5 days |

## Summary table

| Rank | Feature | Value | Effort | Wave |
| --- | --- | --- | --- | --- |
| 1 | Stationary speed 0 on the HUD | high | ~1 day | 1 |
| 2 | Dark offline map + theme choice | high | 2–3 days | 1 |
| 3 | Live Activity | medium–high | 2–3 days | 1 |
| 4 | Lean band (kinematic) | high (motorcycle) | 3–4 days | 2 |
| 5 | Comet tail | medium | ~1 day | 2 |
| 6 | KMZ gx:Tour | medium | 1–2 days | 3 |
| 7 | Track name + stored statistics | medium | 1–2 days | 3 |
| 8 | Postcard share | medium | 2–3 days | 3 |
| 9 | Corner gallery | medium (motorcycle) | 2–3 days | 3 |
| 10 | Manual pause / laps | medium | 2–3 days | 4 |
| 11 | Replay on the map | medium | 5–8 days | 4 |
| 12 | Control Center / Shortcuts | low–medium | ~1 day | any time |
| 13 | Two tracks on one map | low | 2–3 days | later |
| 14 | Elevation sculpture | low | 3–5 days | later |

If only two: **dark offline map** and **Live Activity**. The first shows at night, the second on every recording with the phone away.
For the motorcycle audience, third: **lean band** with kinematic lean.

## Permissions and declarations at a glance

What needs a new entry in the Info.plist, the privacy manifest, the developer portal, or App Store Connect. No item needs a new background mode, Always location, tracking permission (ATT), or the push notification capability.

| # | Item | User permission prompt | Info.plist | Privacy manifest | New target / bundle ID | App Store Connect |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Stationary speed 0 | none | — | — | — | — |
| 2 | Dark map + theme | none | — | — (`UserDefaults` already declared) | — | — |
| 3 | Live Activity | none | `NSSupportsLiveActivities` | the extension's own, if it uses a required-reason API | yes: Widget Extension | one sentence in the review notes |
| 4 | Lean band | none (motion permission already exists) | — | — | — | — |
| 5 | Comet tail | none | — | — | — | — |
| 6 | KMZ gx:Tour | none | — | — | — | — |
| 7 | Name + statistics | none | — | — | — | — |
| 8 | Postcard | **yes, on Save Image: Photos add-only** | **`NSPhotoLibraryAddUsageDescription`** (EN + HU) | — | — | label unchanged; one sentence in the policy |
| 9 | Corner gallery | none | — | — | — | — |
| 10 | Manual pause | none | — | — | — | — |
| 11 | Replay | none | — | — | — | — |
| 12 | Control Center / Shortcuts | none | — | — | widget extension for the Control Center control (shared with item 3) | — |
| 13 | Two tracks | none | — | — | — | — |
| 14 | Elevation sculpture | none | — | — | — | — |

Two items need new declarations: **3 (Live Activity)** and **8 (Postcard)**. Item 12 only if item 3's extension does not exist yet.

## At the end of every wave

- README-en.md and README-hu.md feature lists.
- Help EN/HU for every new control.
- The Info.plist keys, privacy manifests, and targets listed in "Permissions and declarations at a glance" are present in the Release build (check the `Info.plist` inside the built `.app`).
- Privacy policy only if the data flow changes (none of the items above should change it; item 3 and item 8 must be checked).
- Store screenshots: 1320×2868 PNG, RGB, no alpha, from the running build. What's New in both languages.
- A real-iPhone locked-screen walk before each submission, because waves 1, 2, and 4 touch the recording or the map while recording.

## Open decisions (per wave, before implementation)

Wave 1:

- Dark offline style: a hand-made dark JSON, or a programmatic recolor of the light layers? Separate tuning for Turistautak?
- Live Activity update interval within the ActivityKit budget (for example 5 seconds or every accepted point, whichever is less frequent).

Wave 2:

- Lean: band beside the line, or a speed / lean color switch?
- Live lean: gyroscope yaw rate, or only bearing change (about one fix late)?

Record these in the wave's brief; the roadmap does not freeze the pixel layout on purpose.
