User: here is what i want to build i have a mobile app idea. i am calling it monyx for now. i want it built on flutter and be available on ios and android. i want it to be similar to the onx hunt app in some respects, with one big difference. i want it to show you location on a map - ideally being very reliable in bad cell service areas - where you can login, pin locations on the map, and get information about the location you are in like current weather conditions and view borders between private and public land. this is pretty similar to onx so far. the difference i want to add is that you can setup different profiles for yourself for your rifle and ammunition setup, then on the map you can easily drop a pin on a points and it will run an advanced ballistics simulation - what ever the best one is - and easily and quickly tell you what corrections you have to make on your scope/hold off in inches and moa. let's plan how to go about developing this app. What i am describing is basically: 1. an offline-first hunting map app, 2. with land-ownership overlays and weather, 3. plus a serious ballistic calculator tied directly to pinned map targets. ## Product definition At a high level, the monyx app has five core systems: _ **Auth + profiles** _ user account _ saved pins _ saved rifle/ammo profiles _ synced preferences _ **Mapping + offline positioning** _ live GPS location _ offline maps / cached map regions _ dropped pins / waypoints / notes _ route or line-of-sight later, if you want it _ **Land data** _ public vs private boundaries _ parcel boundaries / ownership where legally available _ hunting-relevant overlays _ **Environmental data** _ current weather at user position or pin _ wind, temperature, pressure, humidity _ ideally local atmospheric inputs for ballistic correction _ **Ballistics** _ rifle / optic / ammo profiles _ target pin calculation _ drop / drift / elevation / wind hold _ outputs in inches, MOA, MIL, clicks, holdover _ **v1 prototype / technical validation:** implement a high-quality point-mass solver first, then decide whether to replace it later. _ A map app with hunting overlays is straightforward engineering. _ A ballistic solver that users trust in the field is a credibility and liability problem, not just a coding problem. ## architecture ### Client _ **Flutter** for iOS + Android _ Native platform channels only where needed: _ foreground/background location handling _ sensor access if needed later _ low-level offline map hooks if plugin support is weak ### Backend Use a normal API backend, not Firebase-only. Recommended: _ **Flutter app** _ **Backend API**: Go, .NET, or Node _ **Postgres + PostGIS** _ **Object storage** for offline map region manifests, user exports, imagery references _ **Redis** optional for caching weather / tile metadata Why PostGIS: _ pins, boundaries, parcel geometries, public-land polygons, geospatial queries _ “which parcel/public polygon contains this lat/lon?” becomes a first-class database operation ### Suggested services split _ **Auth service** _ **Map/overlay service** _ **Ballistics service** _ **Weather service adapter** _ **Sync service for offline changes** ## Map stack recommendation Mapbox has an official Flutter SDK and official offline map support via style packs and tile regions, which is a major advantage for a product that must work in bad/no-service areas. ([Mapbox][2]) ## Land boundary data recommendation This is another make-or-break decision. You need: _ public land boundaries _ private parcel boundaries _ ownership or at least parcel identity _ clear legal terms for mobile display and caching Regrid explicitly offers parcel and tile APIs for U.S. and Canadian coverage and positions them for embedding parcel boundaries and parcel lookup in apps. ([regrid.com][4]) My recommendation: _ **Start with licensed parcel/public-land data** _ do not try to stitch this together county-by-county yourself for a commercial v1 Important nuance: _ “private vs public” sounds simple, but coverage quality, update frequency, redistribution rights, and offline use rights vary a lot by provider and jurisdiction. _ This must be solved contractually, not just technically. ## Weather recommendation For current conditions and forecast, Open-Meteo is attractive for prototyping and even some production use cases. Their docs state they aggregate multiple national models, provide worldwide forecast APIs, and do not require an API key for non-commercial use. ([Open Meteo][5]) For ballistics, the specific weather inputs that matter most are: _ wind speed and direction _ temperature _ pressure / station pressure if available _ humidity _ density altitude derived from those inputs Design it so the app can use: 1. live weather API values, 2. manual shooter-entered values, 3. eventually a Bluetooth weather meter. That fallback matters because weather API data is not the same as exact conditions at the firing point. ## Ballistics recommendation This is the product core, so I would design it in layers: ### Layer 1: profile model Per rifle profile: _ rifle name _ caliber _ barrel length _ twist rate _ zero distance _ sight height _ optic unit preference: MOA / MIL _ click value _ muzzle velocity _ muzzle velocity temp sensitivity if supported _ ammo / bullet profile _ drag model inputs ### Layer 2: target solution inputs For a dropped pin: _ shooter lat/lon/elevation _ target lat/lon/elevation _ line-of-sight range _ shooting angle _ wind _ atmosphere _ azimuth / Coriolis later if you want advanced output ### Layer 3: solver A credible early solver can be a point-mass 3-DoF style model with drag tables, spin drift, and atmospheric correction. Open-source examples like pyballistic describe themselves as point-mass small-arms trajectory calculators with support for standard drag tables and custom drag data. ([GitHub][6]) But for a serious commercial differentiator, the market benchmark is higher: _ Applied Ballistics emphasizes custom drag models and a large bullet library. ([Applied Ballistics][1]) _ Hornady emphasizes 4DOF-based trajectory solutions. ([Hornady Manufacturing, Inc][7]) ## UX concept The product must be extremely fast in the field. A good target workflow would be: 1. Open map 2. App locks user location 3. User selects active rifle profile 4. User taps target on map 5. App computes: _ range _ elevation difference _ shot angle _ weather-adjusted solution 6. Show one clean card: _ distance _ up/down correction _ wind correction _ hold in inches _ MOA / MIL _ scope clicks _ confidence / assumptions used This needs a **one-hand field UX**, not a “calculator screen with 40 inputs.” ## Reliability in bad service areas This should be a first-class engineering requirement. The app should work in four states: _ **online** _ full sync, full weather, full data refresh _ **weak service** _ cached tiles, cached overlays, delayed weather refresh _ **offline with cached region** _ GPS still works _ map works _ saved land overlays work _ last-known weather or manual weather _ full ballistic calculation still works locally _ **offline with no cached region** _ no basemap _ still show coordinate grid, pins, and calculations if possible Important point: GPS does not require cell service; map tiles and remote APIs do. Your app should therefore separate: _ **positioning** _ **map rendering** _ **data freshness** _ **calculation engine** That architecture is what makes the product feel reliable. ## MVP scope Do not start with the full vision. Start here: ### MVP v1 _ email / Apple / Google login _ live GPS on map _ download offline map areas _ drop/save pins _ one active rifle profile _ basic ammo profile _ current weather at user / target _ public/private land overlay _ ballistic solution for a dropped target pin _ outputs in inches + MOA + clicks ### v1.1 _ multiple rifle/ammo profiles _ wind direction UI _ MIL output _ manual atmospheric overrides _ shot history ### v1.2 _ offline overlay packs _ profile sharing / export _ range card generation _ multi-target mode ### later _ Bluetooth weather meters _ Bluetooth rangefinder integration _ device compass / inclinometer integration _ reticle view / hold visualization _ 3D terrain line-of-sight _ team/shared maps **Stack** _ Flutter _ Mapbox first _ Postgres/PostGIS backend _ Open-Meteo for early weather \* custom point of mass solver leveraging pyballistic if possible (it's open source so can simply rewrite the pieces we need) [1]: https://appliedballisticsllc.com/ab-quantum/?utm_source=chatgpt.com "AB Quantum™ - Applied Ballistics" [2]: https://docs.mapbox.com/flutter/maps/guides/?utm_source=chatgpt.com "Maps SDK for Flutter - Mapbox Docs" [3]: https://pub.dev/packages/maplibre_gl?utm_source=chatgpt.com "maplibre_gl | Flutter package - Pub" [4]: https://regrid.com/api?utm_source=chatgpt.com "Regrid Parcel API and Tiles: U.S. and Canadian Coverage" [5]: https://open-meteo.com/en/docs?utm_source=chatgpt.com "️ Docs | Open-Meteo.com" [6]: https://github.com/dbookstaber/pyballistic/?utm_source=chatgpt.com "GitHub - dbookstaber/pyballistic: Point-mass ballistic trajectory ..." [7]: https://www.hornady.com/4dofapp?utm_source=chatgpt.com "Hornady Ballistics App ‑ with 4DOF® ‑ Hornady Manufacturing, Inc"

GitHub Copilot:

Read [](file:///c%3A/Users/marku/OneDrive/Documents/Programming/repos/monyx/README.md)

Analyzing your answers...

Good context. .NET backend, solo dev, Dart-native ballistics, and some Flutter experience. Let me draft your development plan.

Created memory file [](file:///c%3A/Users/marku/AppData/Roaming/Code/User/workspaceStorage/58cc66de92cfb9eb0a74d918f0f33ca9/GitHub.copilot-chat/memory-tool/memories/NzliMDA1ZDUtYzkxOS00N2QzLThhZWQtZGM5OTAwYjZiYzhm/plan.md)

Here's the full development plan for Monyx.

---

## Plan: Monyx — Offline Hunting Map + Ballistics App

**TL;DR:** Offline-first Flutter app with Mapbox maps, Regrid land overlays, Open-Meteo weather, and a Dart-native point-mass ballistic solver. .NET 8 API backend on Postgres/PostGIS, deployed to Azure. Six phases, targeting ~12 weeks solo.

---

### Phase 0 — Project Scaffolding & Tooling (Week 1)

1. Initialize Flutter project (`monyx/`) targeting iOS 15+ / Android API 26+
2. Set up .NET 8 Web API (`backend/Monyx.Api/`) with feature-folder structure (Auth, Map, Weather, Ballistics, Sync)
3. Provision Postgres 16 + PostGIS + Redis locally via Docker Compose
4. GitHub Actions CI — two jobs: `flutter analyze + test`, `dotnet build + test`
5. Configure Mapbox account + add `mapbox_maps_flutter` package
6. Configure Regrid developer account for parcel tile/API access
7. Set up Open-Meteo adapter abstraction (no key needed for dev)

---

### Phase 1 — Auth + Core Navigation (Weeks 2–3)

1. **Backend auth:** JWT-based auth via ASP.NET Identity on Postgres (EF Core). Email/password + Apple Sign-In + Google Sign-In as OAuth2 external providers
2. **Flutter auth:** `flutter_secure_storage` for tokens, login/register screens, token refresh
3. **App shell:** Bottom nav — **Map**, **Profiles**, **Settings**. `go_router` for navigation
4. **User prefs model:** Unit system, default optic unit (MOA/MIL)
5. **DB migrations:** EF Core migrations, seed PostGIS extension

_Verification:_ Register, login, JWT issued, protected endpoints work, OAuth flows work on device.

---

### Phase 2 — Mapping + Offline + Pins (Weeks 3–5)

1. **Mapbox integration:** Satellite/topo map with live user location
2. **GPS handling:** Foreground + background via `geolocator`. Verify no network dependency in the location pipeline
3. **Offline map regions:** Mapbox `OfflineManager` — user selects region to download, progress UI, storage indicator. Region metadata in local SQLite (`drift` package)
4. **Pin system:**
   - Backend: `Pins` table with PostGIS `geography(Point, 4326)`, user FK, name, notes, timestamps
   - Flutter: tap-to-drop, pin detail sheet (name, notes, coordinates, elevation), local SQLite persistence
5. **Basic offline sync:** Pins marked `pending_sync`, pushed to server on connectivity. Last-write-wins for v1
6. **Elevation data:** Mapbox terrain tileset or DEM query for user + pin positions (critical for ballistic angle)

_Verification:_ Download offline region → airplane mode → map renders, GPS dot moves, pins persist, sync works when back online.

---

### Phase 3 — Land Ownership Overlays (Weeks 5–6) _parallel with Phase 4_

1. **Regrid backend adapter:** Proxy + Redis-cache parcel tile requests and parcel-info lookups. Store public-land polygons in PostGIS for offline serving
2. **Public/private overlay:** Colored boundary layer on Mapbox via `GeoJsonSource` or backend-served vector tiles
3. **Parcel tap info:** Card with owner name (where legal), acreage, parcel ID
4. **Offline overlay cache:** Public/private boundary GeoJSON cached locally for downloaded regions

_Verification:_ Public land boundaries visible on map, parcel info on tap, boundaries render in airplane mode.

---

### Phase 4 — Weather Integration (Weeks 6–7) _parallel with Phase 3_

1. **Backend adapter:** Open-Meteo API for current conditions at lat/lon — temp, humidity, pressure, wind speed/direction, precipitation. Redis cache (5-min TTL)
2. **Flutter weather card:** Collapsible card on map screen. Auto-fetch weather when dropping target pins. Cache last-fetched locally
3. **Manual override UI:** User-entered temp, pressure, humidity, wind — overrides API values for ballistics. Field shooters need this
4. **Density altitude computation:** Derived from temp + pressure + humidity, displayed on card, fed to solver

_Verification:_ Weather shows at user location, pin drops trigger weather fetch, manual overrides persist, last-known weather available offline.

---

### Phase 5 — Ballistic Solver (Weeks 7–10) — CRITICAL PATH

**5a: Dart solver port**

1. Study pyballistic (Python, MIT license) — point-mass 3-DoF, G1/G7 drag tables, atmospheric correction, spin drift
2. Port to pure Dart as `packages/ballistics_engine/` — no Flutter dependency, independently testable
   - Core types: `RifleProfile`, `AmmoProfile`, `AtmosphericConditions`, `TargetSolution`, `TrajectoryPoint`
   - Drag tables: G1 + G7 as const arrays
   - Solver: RK4 integration of point-mass equations
   - Atmospheric model: air density from temp/pressure/humidity → drag coefficient adjustment
   - Output: trajectory at 1-yd increments — drop (in), drift (in), velocity, energy, TOF, MOA, MIL corrections
3. **Validate against known data:** Compare vs JBM Ballistics / Applied Ballistics for .308 175gr SMK, 6.5CM 140 ELD-M, .223 77gr SMK. Target: **< 0.5 MOA deviation at 1000 yards**
4. **Performance:** Full trajectory to 2000y in **< 50ms** on mid-range phone

**5b: Rifle + ammo profiles** 5. Backend + local model: caliber, barrel length, twist rate/direction, sight height, zero distance, zero conditions, optic unit, click value, bullet BC (G1/G7), muzzle velocity, MV temp sensitivity 6. Flutter CRUD: Profiles screen (list/create/edit/delete), profile picker on map screen

**5c: Map-integrated shot solution** 7. Target pin computation: slant range (haversine + elevation delta → LOS range), shot angle, azimuth for wind decomposition, atmosphere from weather/cache/manual → solver → `TargetSolution` 8. **Solution card UI** — one-hand field UX:

- Range (yards), elevation correction (in / MOA / MIL / clicks), wind correction (in / MOA / MIL / clicks), shot angle, atmospheric summary, density altitude
- **Confidence indicator:** green (live weather + good GPS) / yellow (cached weather) / red (manual/estimated)
- Swipe to dismiss, tap to expand full trajectory table

_Verification:_ Create .308 175gr profile, zero 100y, drop pin at known 500y → compare output vs JBM. < 0.5 MOA drop deviation, < 0.3 MOA wind at 10 mph crosswind. Computes in < 100ms. Full flow works in airplane mode.

---

### Phase 6 — Polish + MVP Launch (Weeks 10–12)

1. Four-state connectivity model (online / weak / offline-cached / offline-no-cache) with indicator
2. Error handling: missing elevation, no weather, extreme range, invalid profiles
3. Unit system toggle (metric / imperial) app-wide
4. Onboarding tutorial: download first region, create first profile, drop first target
5. App icon, splash screen, app store metadata
6. **Deploy backend to Azure:** App Service (B1 ~$30/mo) + PostgreSQL Flexible Server + Blob Storage
7. TestFlight + Google Play internal testing

_Verification:_ Full end-to-end on physical device in airplane mode. `flutter analyze` clean. TestFlight + internal track installs succeed.

---

### Project Structure

```
monyx/
  lib/
    features/auth/         — login, register, auth state
    features/map/          — map screen, pins, offline regions
    features/land/         — land overlay rendering, parcel info
    features/weather/      — weather card, manual overrides
    features/ballistics/   — shot solution UI, profile picker
    features/profiles/     — rifle/ammo CRUD
  packages/
    ballistics_engine/     — pure Dart solver (no Flutter dep)
backend/
  Monyx.Api/
    Features/Auth/         — ASP.NET Identity + JWT
    Features/Pins/         — Pin CRUD + PostGIS
    Features/Land/         — Regrid proxy + cache
    Features/Weather/      — Open-Meteo adapter
    Features/Profiles/     — Rifle/ammo profile CRUD + sync
docker-compose.yml         — Postgres+PostGIS, Redis
```

---

### Key Decisions

| Decision                                   | Rationale                                                                                                     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| **Solver runs on-device in Dart**          | Fully offline, no server needed for calculations                                                              |
| **Backend: .NET 8**                        | Your preference + natural Azure fit                                                                           |
| **Local SQLite via `drift`**               | Pins, profiles, weather cache, overlays all local-first. Server is sync target, not field-use source of truth |
| **Mapbox (not MapLibre)**                  | Official Flutter SDK with built-in offline support worth the cost                                             |
| **Regrid for land data**                   | Licensed parcel data, not DIY county stitching                                                                |
| **Open-Meteo for weather**                 | Free for prototyping, upgradeable later                                                                       |
| **Point-mass 3-DoF for v1**                | Credible for field use, upgradeable to 4-DoF later                                                            |
| **Azure hosting**                          | App Service + PostgreSQL Flexible + Blob. ~$30-50/mo at MVP scale                                             |
| **MOA + MIL + inches + clicks all in MVP** | Per your spec                                                                                                 |

### Scope Boundaries

**In MVP:** Auth (email/Apple/Google), GPS + offline maps, pin drop + sync, public/private land overlay, weather + manual overrides, one active rifle/ammo profile, ballistic solution (drop, wind, MOA, MIL, clicks), offline operation.

**Excluded from MVP:** Multiple simultaneous profiles, shot history, range cards, Bluetooth integrations, compass/inclinometer, reticle visualization, 3D terrain LOS, team maps, Coriolis correction.

---

### Cost Considerations

- **Mapbox:** Free tier covers 25K MAU — effectively free during dev/beta
- **Regrid:** Developer tier ~$200/mo. **If too expensive for prototyping**, start with free USGS/BLM public-land data only (no private parcels) and add Regrid later
- **Azure:** ~$30-50/mo at MVP scale
- **Open-Meteo:** Free for non-commercial; commercial license available

### Liability Note

Ballistic calculator outputs must include a clear disclaimer (estimates only, user responsible for all decisions). Standard industry practice — Applied Ballistics, Hornady, etc. all do this.

---

Ready for your review. Let me know what to adjust — scope, sequencing, tech choices, or anything else.

User: i want to get up and running as fast as possible with the following ux. launch app, my location is plotted on a map, i press a button to create rilfe+ammunition profile, i go back to the map, i drop a pin at some other close by location and the elevation/distance/weather is used to do the ballistic calculation. I am shown the up/down and left/right offselts to make on my scope in inches and moa

GitHub Copilot:

Read memory [](file:///c%3A/Users/marku/AppData/Roaming/Code/User/workspaceStorage/58cc66de92cfb9eb0a74d918f0f33ca9/GitHub.copilot-chat/memory-tool/memories/NzliMDA1ZDUtYzkxOS00N2QzLThhZWQtZGM5OTAwYjZiYzhm/plan.md)

Analyzing your answers...

Created memory file [](file:///c%3A/Users/marku/AppData/Roaming/Code/User/workspaceStorage/58cc66de92cfb9eb0a74d918f0f33ca9/GitHub.copilot-chat/memory-tool/memories/NzliMDA1ZDUtYzkxOS00N2QzLThhZWQtZGM5OTAwYjZiYzhm/vertical-slice-plan.md)

Here's a stripped-down vertical-slice plan to get the core loop running as fast as possible — no backend, no auth, no land overlays. Pure Flutter, everything on-device.

---

## Plan: Monyx Vertical Slice — Map → Profile → Pin → Solution

**TL;DR:** Get the one UX loop working end-to-end: launch app → see yourself on map → create rifle profile → drop target pin → see ballistic solution card with inches + MOA + clicks. Skip everything else for now.

---

### Prerequisites (before any code)

- **Sign up at mapbox.com** → create an access token (you'll need both a public token and a secret/download token for SDK access)
- Flutter SDK installed, `flutter doctor` clean
- Xcode + Simulator, Android Studio + emulator ready

---

### Step 1: Flutter project + Mapbox map with GPS

1. Initialize Flutter project in the repo root (or a subfolder)
2. Add dependencies: `mapbox_maps_flutter`, `geolocator`, `permission_handler`, `go_router`, `flutter_riverpod`, `http`, `shared_preferences`
3. Configure Mapbox tokens — Android: secret token in `gradle.properties`, public token in app. iOS: secret token in `~/.netrc`, public token in app
4. Build `MapScreen` — full-screen Mapbox map (satellite-streets style), request location permission on launch, show user location puck, center on user
5. Single-route app: `MaterialApp.router` → `MapScreen`

**Verify:** App launches, map loads, blue dot at your location.

---

### Step 2: Rifle + ammo profile (local-only)

1. Data models — `RifleProfile` (name, caliber, barrel length, twist rate, sight height, zero distance, optic unit MOA, click value) + `AmmoProfile` (name, bullet weight, BC G1, BC G7, muzzle velocity). Plain Dart + JSON serialization
2. `ProfileScreen` — form with all fields, pre-filled with a sensible default (.308 Win 175gr SMK, 2650 fps, 0.505 G1, 1.5" sight height, 100yd zero, ¼ MOA clicks). Save to `shared_preferences`
3. FAB on map screen → navigate to profile → save → back to map
4. Riverpod provider exposes current profile app-wide

**Verify:** Create profile, save, restart app — profile persists.

---

### Step 3: Drop target pin on map

1. Long-press on map → drop pin via Mapbox `PointAnnotationManager`
2. On pin drop, capture:
   - User's current lat/lon from GPS
   - User's elevation + pin's elevation from **Mapbox terrain query**
   - Pin's lat/lon from tap coordinate
3. Compute: horizontal distance (haversine), elevation delta, slant range, shot angle

**Verify:** Long-press → pin appears, coordinates + elevation captured.

---

### Step 4: Weather fetch

1. On pin drop, HTTP GET to Open-Meteo: `https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,relative_humidity_2m,surface_pressure,wind_speed_10m,wind_direction_10m`
2. Parse into `WeatherData`: temp (°F), humidity, pressure (inHg), wind speed (mph), wind direction
3. If fetch fails → fall back to ICAO standard atmosphere (59°F, 29.92 inHg, 50% humidity, 0 wind) with a "weather estimated" indicator

**Verify:** Pin drop triggers weather fetch, values logged.

---

### Step 5: Ballistic solver (Dart, on-device) — heaviest step

1. `lib/ballistics/drag_tables.dart` — G1 and G7 Cd-vs-Mach tables as const arrays
2. `lib/ballistics/atmosphere.dart` — air density from temp/pressure/humidity (ICAO model), speed of sound, density altitude
3. `lib/ballistics/solver.dart` — **Point-mass 3-DoF, RK4 integration:**
   - First pass: iteratively find zero angle (launch angle that yields zero drop at zero range under zero-day conditions)
   - Second pass: compute full trajectory to target range with current atmosphere + wind + shot angle
   - Output at target: drop (inches), windage (inches), velocity, TOF
4. `lib/ballistics/conversions.dart` — inches → MOA: `(inches / range_yards) × (100 / 1.047)`, MOA → clicks: `moa / clickValue`
5. Validate with unit tests: .308 175gr SMK at 500y should produce ~48" drop, ~8 MOA. Compare against JBM Ballistics — target < 0.5 MOA deviation

**Verify:** `flutter test` passes, solver output matches known ballistic data.

---

### Step 6: Solution card UI

On pin drop → solver runs → show bottom sheet:

```
┌──────────────────────────────┐
│  TARGET SOLUTION             │
│  Range: 523 yds              │
│  ────────────────────────    │
│  ↕ Elevation                 │
│    42.3"  │  8.1 MOA UP      │
│    32 clicks UP              │
│  ────────────────────────    │
│  ↔ Wind (R→L 8 mph)         │
│    6.2"   │  1.2 MOA LEFT    │
│    5 clicks LEFT             │
│  ────────────────────────    │
│  Angle: +3.2°  DA: 4,520 ft │
│  🟢 Live weather             │
└──────────────────────────────┘
```

- `showModalBottomSheet` or `DraggableScrollableSheet`
- Green = live weather, yellow = cached, red = estimated defaults
- Dismiss by swipe or tap outside

**Verify:** Full loop — launch → location → create profile → drop pin → solution card with inches + MOA + clicks for both elevation and wind.

---

### File Structure

```
lib/
  main.dart                     — Entry, router, providers
  screens/
    map_screen.dart             — Map + GPS + pin + solution trigger
    profile_screen.dart         — Rifle/ammo form
  models/
    rifle_profile.dart          — Data classes + JSON
    weather_data.dart           — Open-Meteo response model
    shot_solution.dart          — Solver output model
  ballistics/
    drag_tables.dart            — G1/G7 tables
    atmosphere.dart             — Air density, speed of sound, DA
    solver.dart                 — RK4 point-mass solver
    conversions.dart            — Unit conversions
  services/
    weather_service.dart        — Open-Meteo HTTP
    terrain_service.dart        — Elevation queries
    profile_service.dart        — SharedPreferences I/O
  widgets/
    solution_card.dart          — Bottom sheet UI
test/
  ballistics/
    solver_test.dart            — Validate against known data
```

### Dependencies

`mapbox_maps_flutter`, `geolocator`, `permission_handler`, `go_router`, `flutter_riverpod`, `http`, `shared_preferences`

---

### What this deliberately skips

- No backend, no auth, no sync
- No land overlays
- No offline map downloads
- No multiple profiles (one active profile only)
- No MIL output (inches + MOA + clicks only)
- No shot history, no manual weather overrides
- No Coriolis, no spin drift
- Imperial only, no metric toggle

All of those get layered on after the core loop works. This plan is 6 steps to a working prototype you can test in the field.

---

Ready for your review. Want to adjust anything, or should we start building?
