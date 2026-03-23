# monyx

Offline-first hunting map with instant on-map ballistic calculations. Drop a pin on the map, and get scope corrections (elevation + wind) in inches, MOA, and clicks — using your rifle profile, real weather, and terrain elevation.

## POC Architecture

The proof-of-concept is a **pure Flutter app with no backend**. Everything runs on-device:

```
┌─────────────────────────────────────────────┐
│                 Flutter App                 │
├──────────┬──────────┬───────────┬───────────┤
│  Map     │ Profiles │  Weather  │ Ballistics│
│  Screen  │  Screen  │  Service  │  Engine   │
├──────────┴──────────┴───────────┴───────────┤
│  BLoC state management                      │
├─────────────────────────────────────────────┤
│  Hive (local cache)    GPS (geolocator)     │
├─────────────────────────────────────────────┤
│  Mapbox SDK         Open-Meteo API          │
└─────────────────────────────────────────────┘
```

**Core loop:** Launch → GPS plots you on the map → Create a rifle/ammo profile → Long-press to drop a target pin → App computes range, elevation delta, fetches weather → Dart ballistic solver runs on-device → Solution card shows UP/DOWN and LEFT/RIGHT corrections in inches + MOA + clicks.

### Key tech choices

| Layer         | Tech                           | Why                                             |
| ------------- | ------------------------------ | ----------------------------------------------- |
| UI framework  | Flutter (iOS + Android)        | Single codebase, native performance             |
| Maps          | Mapbox Maps Flutter SDK        | Official offline support, satellite imagery     |
| State         | BLoC pattern (`flutter_bloc`)  | Predictable state, testable, industry standard  |
| Local storage | Hive                           | Fast NoSQL cache, no native deps, works offline |
| GPS           | `geolocator`                   | Cross-platform location with background support |
| Weather       | Open-Meteo API                 | Free, no API key for dev, worldwide coverage    |
| Ballistics    | Custom Dart solver (on-device) | Works fully offline, point-mass 3-DoF model     |

## Ballistic Engine

The solver is a pure-Dart port of [pyballistic](https://github.com/dbookstaber/pyballistic) (py-ballisticcalc), a well-tested open-source ballistic calculator. All calculations run on-device with no network required.

### Algorithm

| Component                | Detail                                                                                          |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| **Model**                | Point-mass 3-DoF (x = downrange, y = drop, z = windage)                                         |
| **Integrator**           | Classic RK4, fixed time step 0.0025 s                                                           |
| **Drag tables**          | Standard G1 (80 entries) and G7 (84 entries), Cd vs Mach                                        |
| **Drag interpolation**   | PCHIP (monotone cubic Hermite, Fritsch-Carlson slopes) — C1 continuous, shape-preserving        |
| **Standard Drag Factor** | `Cd(mach) × 2.08551e-04 / BC` where the constant = ρ₀ × π / (4 × 2 × 144), ρ₀ = 0.076474 lb/ft³ |
| **Air density**          | CIPM-2007 formula — saturation vapour pressure, enhancement factor, compressibility factor      |
| **Altitude correction**  | Lapse-rate model (−0.0019812 K/ft) updates density ratio and Mach at each integration step      |
| **Speed of sound**       | 49.0223 × √(°R) ft/s                                                                            |
| **Zero-finding**         | Ridder's method (guaranteed convergence, ~60 iterations max)                                    |
| **Gravity**              | 32.17405 ft/s²                                                                                  |

### How a shot is solved

1. **Build atmosphere** — station temperature, pressure, humidity → CIPM-2007 air density in kg/m³ → density ratio (local / standard 1.225 kg/m³).
2. **Find zero angle** — under ICAO standard atmosphere, find the bore elevation (via Ridder's method) that puts the bullet at y = 0 at the zero range.
3. **Add shot angle** — if the target has an elevation difference (from DEM), the look angle is added to the zero angle.
4. **Run trajectory** — RK4 integration with altitude-dependent density and Mach. At each step: compute `k_m = density_ratio × drag_by_mach(speed/Mach)` once, then evaluate four sub-step accelerations (gravity + drag opposing air-relative velocity). Wind is a constant headwind/crosswind vector subtracted from ground velocity.
5. **Measure drop** — the line-of-sight from scope (at sight height) to target (at elevation offset) is computed at the bullet's final x position. Drop = bullet y − LOS y. Windage = bullet z.
6. **Convert** — drop/drift in inches → MOA → clicks, plus velocity, energy, and time of flight.

### Test data

The solver is validated against pyballistic's reference trajectories:

| Profile                                | Range   | Velocity | Drop   | Source                   |
| -------------------------------------- | ------- | -------- | ------ | ------------------------ |
| .308 168gr BC 0.223 G1, MV 2750, 2" SH | 100 yd  | 2351 fps | 0"     | pyballistic test_path_g1 |
| .308 168gr BC 0.223 G1, MV 2750, 2" SH | 500 yd  | 1169 fps | −87.9" | pyballistic test_path_g1 |
| .308 168gr BC 0.223 G1, MV 2750, 2" SH | 1000 yd | 776 fps  | −824"  | pyballistic test_path_g1 |
| .308 168gr BC 0.223 G7, MV 2750, 2" SH | 100 yd  | 2545 fps | 0"     | pyballistic test_path_g7 |
| .308 168gr BC 0.223 G7, MV 2750, 2" SH | 500 yd  | 1814 fps | −56.2" | pyballistic test_path_g7 |
| .308 168gr BC 0.223 G7, MV 2750, 2" SH | 1000 yd | 1086 fps | −400"  | pyballistic test_path_g7 |

Tolerances: velocity ±15 fps, drop ±3" (500 yd) / ±10" (1000 yd).

### What the POC deliberately skips

- No backend / no auth / no sync
- No land ownership overlays
- No offline map downloads
- No MIL output (inches + MOA + clicks only)
- No shot history
- Imperial units only

## Dev Environment Setup (macOS)

### Prerequisites

- **Flutter SDK** (stable channel, 3.41+)
- **Xcode** with iOS Simulator installed
- **Android Studio** with Android SDK 36+
- **CocoaPods** (`brew install cocoapods`)
- **Mapbox account** with two tokens (see below)

### 1. Clone and install dependencies

```bash
git clone <repo-url> && cd monyx
flutter pub get
```

### 2. Mapbox token setup

You need **two** Mapbox tokens. Neither is stored in the repo.

#### Public token (used at runtime in the app)

Create a public token at [mapbox.com/account/access-tokens](https://account.mapbox.com/access-tokens/) with default scopes:

- `styles:tiles`, `styles:read`, `fonts:read`, `datasets:read`

Then create a `.env` file in the project root (gitignored):

```bash
cp .env.example .env
# Edit .env and paste your public token
```

```
MAPBOX_PUBLIC_TOKEN=pk.your_token_here
```

#### Secret token (used at build time to download the SDK)

Create a **secret** token with the `downloads:read` scope. This token is used by CocoaPods (iOS) and Gradle (Android) to authenticate when downloading the Mapbox SDK binary. It never ships in the app.

**iOS — `~/.netrc`**

Add to `~/.netrc` (create it if it doesn't exist):

```
machine api.mapbox.com
  login mapbox
  password sk.your_secret_token_here
```

Then restrict permissions:

```bash
chmod 600 ~/.netrc
```

> `~/.netrc` is a standard Unix credential file. Tools like `curl`, CocoaPods, and Gradle read it to authenticate HTTP requests. Mapbox's CocoaPods spec fetches the SDK from `api.mapbox.com` and uses `~/.netrc` for auth automatically.

**Android — `~/.gradle/gradle.properties`**

Add to `~/.gradle/gradle.properties` (create if needed):

```properties
SDK_REGISTRY_TOKEN=sk.your_secret_token_here
```

### 3. Verify setup

```bash
flutter doctor        # Should show no issues
```

## Build, Test & Run

All commands should be run from the project root.

### Analyze (lint)

```bash
flutter analyze
```

### Run tests

```bash
flutter test                            # All tests
flutter test test/widget_test.dart      # Ballistics solver tests only
```

### Boot a simulator

**iOS (recommended for dev):**

```bash
open -a Simulator                                           # Opens Simulator.app
xcrun simctl boot "iPhone 15 Pro"                           # Boot a specific device
```

**Android:**

```bash
flutter emulators --launch Nexus_6P_API_34                  # Or whichever AVD you have
```

Check available devices:

```bash
flutter devices
```

### Add test images to the simulator gallery

The iOS Simulator has no camera, so to test **Animal Track Identification** you need to pre-load a photo into the simulator's Photos library. Use `simctl addmedia`:

```bash
xcrun simctl addmedia booted ~/Downloads/deer.jpeg
```

`booted` targets whichever simulator is currently running. You can also use the device name:

```bash
xcrun simctl addmedia "iPhone 15 Pro" ~/Downloads/deer.jpeg
```

The image will appear in **Photos → Recents** inside the simulator. When testing track ID, choose **Photos** (gallery) instead of Camera to pick it.

### Set simulator GPS location

Simulators don't use your Mac's real GPS — they default to San Francisco. Override it:

**iOS Simulator:**

```bash
xcrun simctl location <device-id> set <lat>,<lon>
# Example: Nova Scotia
xcrun simctl location 4873414E-D97C-441E-AB4E-7A842CDCE72E set 45.0618,-63.4050
```

Or via the Simulator app menu: **Features → Location → Custom Location**.

**Android Emulator:**

```bash
adb emu geo fix <lon> <lat>
# Example: Nova Scotia (note: longitude comes first)
adb emu geo fix -63.4050 45.0618
```

Or via Android Studio: **Extended Controls (⋯) → Location** → enter coordinates → **Set Location**.

### Run the app

The Mapbox public token is passed at compile time from `.env` — never hardcoded:

```bash
flutter run --dart-define-from-file=.env                    # Picks first available device
flutter run --dart-define-from-file=.env -d <device-id>     # Target a specific device
```

### Build (release)

```bash
flutter build ios --dart-define-from-file=.env              # iOS archive
flutter build apk --dart-define-from-file=.env              # Android APK
```

### 4. Android SDK note

Flutter 3.41+ requires Android SDK 36. If `flutter doctor` complains:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager "platforms;android-36" "build-tools;36.0.0"
```

## TFLite on iOS — Symbol Stripping Workaround

### The problem

The `tflite_flutter` plugin uses Dart FFI (`dlsym(RTLD_DEFAULT, "TfLiteModelCreate")`) to call TensorFlowLiteC at runtime. On iOS, TensorFlowLiteC v2.12.0 ships as a **static library** for device (arm64) but a **dynamic framework** for the simulator. When statically linked, no Swift/ObjC code in the app references the TFLite C symbols directly — only Dart does, at runtime. The iOS linker and strip tool can't see runtime `dlsym` calls, so they dead-strip and remove the symbols from the release binary. The result: TFLite works on the simulator (dynamic framework → symbols always available) but crashes on physical devices with:

```
Failed to lookup symbol 'TfLiteModelCreate': dlsym(RTLD_DEFAULT, TfLiteModelCreate): symbol not found
```

### The fix (three parts)

All three are required. Removing any one of them causes the symbols to be stripped.

#### 1. `ios/Runner/KeepTfLiteSymbols.m`

A native ObjC file that references TFLite C API functions with `__attribute__((used))`. This creates compile-time references so the linker pulls the symbols from the static library into the binary. The function is never called — its existence is what matters.

#### 2. `DEAD_CODE_STRIPPING = NO` on the Runner target

Set via the Podfile `post_install` block (not globally on pods). Prevents the linker from removing "unreachable" code paths within the static library.

#### 3. `STRIP_STYLE = non-global` on the Runner target

Also set via Podfile `post_install`. After linking, Xcode runs `strip` on the binary. The default strip style removes global symbols. `non-global` keeps them, so `dlsym()` can find `TfLiteModelCreate` at runtime.

**Important:** These settings must only be applied to the **Runner target**, not to all pod targets. Applying `STRIP_STYLE` globally (e.g., in `installer.pods_project.targets`) causes pod frameworks like `objective_c.framework` to retain simulator platform tags, which fails App Store validation.

### What didn't work

| Approach | Why it failed |
| --- | --- |
| `DynamicLibrary.open('TensorFlowLiteC.framework/TensorFlowLiteC')` in Dart | Works on simulator (dynamic framework) but the framework file doesn't exist on device (static lib) |
| `-Wl,-u,_TfLiteModelCreate` in `OTHER_LDFLAGS` | Tells the linker the symbol is needed, but post-link `strip` still removes it |
| `STRIP_STYLE = non-global` on all targets via Podfile | Preserves symbols but also preserves simulator platform tags in pod frameworks → Xcode distribution validation failure |

## Deploy to App Store Connect

### Prerequisites

- Active [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/yr)
- App record created in [App Store Connect](https://appstoreconnect.apple.com) with bundle ID `com.monyx.monyx`
- Xcode signed with your distribution certificate (Runner → Signing & Capabilities → select your team)

### 1. Bump the build number

Each upload requires a unique build number. Increment the `+N` portion in `pubspec.yaml`:

```yaml
version: 1.0.0+3 # +N must be higher than the last uploaded build
```

### 2. Build the release archive

```bash
flutter clean
flutter pub get
flutter build ipa --release --dart-define-from-file=.env
```

This produces an `.xcarchive` in `build/ios/archive/` and an `.ipa` in `build/ios/ipa/`.

### 3. Upload via Xcode

```bash
open build/ios/archive/Runner.xcarchive
```

This opens the Xcode **Organizer** window:

1. Select the archive and click **Distribute App**
2. Choose **App Store Connect** → **Upload**
3. Follow the signing and validation prompts
4. Wait for the upload to complete

### 4. TestFlight

After upload, the build takes ~10–30 minutes to process in App Store Connect:

1. Go to **App Store Connect → TestFlight**
2. Answer the **Export Compliance** question (select "No" if the app only uses HTTPS)
3. **Internal testers** (up to 100) — available immediately, no review needed
4. **External testers** (up to 10,000) — requires a brief Beta App Review

### 5. Submit for App Store review

1. In App Store Connect, go to your app → **App Store** tab
2. Fill in screenshots, description, keywords, promotional text, privacy policy URL, and support URL
3. Select the build from your TestFlight uploads
4. Click **Submit for Review**

> **Important:** The Mapbox public token is baked in at compile time via `--dart-define-from-file=.env`. If you build or archive from Xcode directly (without the Flutter CLI), the token will be empty and the map will show a black screen. Always use `flutter build ipa` first.

## Project Structure

```
lib/
  main.dart                     — Entry point, Hive init, BLoC providers
  config.dart                   — Compile-time env config (--dart-define)
  screens/
    map_screen.dart             — Mapbox map + GPS + pin drop + solution trigger + banner ad
    profile_list_screen.dart    — Profile selector (free: 1, pro: unlimited) + upgrade prompt
    profile_screen.dart         — Rifle/ammo profile form (create/edit)
    track_result_screen.dart    — Full-screen track ID results (annotated image + species list)
    saved_tracks_screen.dart    — List of saved track identification results
    plant_result_screen.dart    — Full-screen plant ID results (photo + species list)
    saved_plants_screen.dart    — List of saved plant identification results
  models/
    rifle_profile.dart          — Rifle + ammo data classes + JSON
    weather_data.dart           — Open-Meteo response model
    shot_solution.dart          — Solver output model
    detection.dart              — Single YOLO bounding-box detection
    track_result.dart           — Saved track identification result
    plant_result.dart           — PlantPart enum, PlantPrediction, PlantResult
    plant_metadata.dart         — Species metadata model for reranking
  ballistics/
    drag_tables.dart            — G1/G7 Cd-vs-Mach tables + PCHIP spline interpolation
    atmosphere.dart             — CIPM-2007 air density, speed of sound, lapse-rate AtmoState
    solver.dart                 — RK4 point-mass 3-DoF solver (pyballistic port)
    conversions.dart            — Inches ↔ MOA ↔ clicks, haversine, wind decomp
  services/
    weather_service.dart        — Open-Meteo HTTP adapter
    elevation_service.dart      — Open-Meteo elevation queries
    profile_service.dart        — Hive persistence for rifle profiles (supports multi-profile)
    ad_service.dart             — AdMob ad-unit IDs (test in debug, real in release)
    subscription_service.dart   — In-app purchase wrapper (StoreKit / Google Play)
    track_detector.dart         — On-device YOLOv11 TFLite inference engine
    track_service.dart          — Hive persistence for saved track results
    plant_classifier.dart       — On-device EfficientNet-Lite0 TFLite classifier
    plant_service.dart          — Hive persistence for saved plant results
    plant_reranker.dart         — Metadata-based reranking (region, season, part)
    region_lookup.dart          — Offline GPS → US state / CA province lookup
  blocs/
    profile_cubit.dart          — Profile load/save/switch state (multi-profile)
    solution_cubit.dart         — Shot solution computation state
    subscription_cubit.dart     — Free/Pro subscription state
    track_cubit.dart            — Track identification flow state
    plant_cubit.dart            — Plant identification flow state
  widgets/
    solution_card.dart          — Bottom sheet with corrections
    detection_image_painter.dart — Bounding-box overlay painter for track photos
assets/
  models/
    footprint_det_float16.tflite — YOLOv11n footprint detector (117 species, ~10 MB)
    feces_det_float16.tflite     — YOLOv11n feces detector (101 species, ~10 MB)
    footprint_classes.json       — Footprint class-name mapping
    feces_classes.json           — Feces class-name mapping
    plant_classifier_float16.tflite — EfficientNet-Lite0 plant classifier (~5–15 MB)
    plant_classes.json           — Plant species class-name mapping
    plant_metadata.json          — Species metadata (regions, months, parts, toxicity)
tools/
  export_models.py              — Download + convert YOLO models to TFLite
  build_plant_dataset.py        — Download iNaturalist plant images
  build_plant_metadata.py       — Build species metadata for reranking
  train_plant_classifier.py     — Train EfficientNet-Lite0 classifier
  export_plant_classifier.py    — Export trained model to TFLite
  requirements.txt              — Python dependencies for model export + training
ios/
  MonyxProducts.storekit        — Xcode StoreKit test configuration
test/
  widget_test.dart              — Ballistics solver smoke tests
```

## Monetisation

The app is free with ads (AdMob). A "Monyx Pro" monthly subscription removes ads and unlocks additional features.

### Ads (Google AdMob)

Banner ads are shown at the bottom of the map screen for free-tier users.

| Item                       | Value                                                                                      |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| **AdMob App ID (iOS)**     | `ca-app-pub-8357274860394786~6932367408`                                                   |
| **Banner Ad Unit (iOS)**   | `ca-app-pub-8357274860394786/5507605098`                                                   |
| **Test/Release switching** | Automatic — `kReleaseMode` in [lib/services/ad_service.dart](lib/services/ad_service.dart) |
| **Banner type**            | Anchored adaptive (auto-sizes to device width)                                             |

**How it works:**

- Debug / simulator builds use Google's test ad unit ID → shows a "Test Ad" label, safe to tap.
- Release builds (`flutter build ipa`) use the real ad unit ID → real ads served.
- The App ID in `ios/Runner/Info.plist` (`GADApplicationIdentifier`) is always the real one — only ad _unit_ IDs switch.
- Pro subscribers never see ads — the banner is not loaded when `SubscriptionCubit` reports `SubscriptionPro`.

### Subscription (In-App Purchase)

| Item           | Value                                                  |
| -------------- | ------------------------------------------------------ |
| **Product ID** | `monyx_pro_monthly_3`                                  |
| **Type**       | Auto-renewable subscription, 1 month                   |
| **Price**      | $4.99/mo (configure in App Store Connect)              |
| **Benefits**   | No ads, unlimited rifle/ammo profiles, animal track ID |

The subscription is managed by `SubscriptionService` → `SubscriptionCubit`. Free users see a single profile, a banner ad, and no track ID access. Pro users see a profile list, no ads, and full access to animal track identification.

**For production**, the subscription is configured in **App Store Connect** — you create the product there with the same product ID (`monyx_pro_monthly_3`), set the price, and submit for review. The app code talks to the real App Store automatically; no code changes are needed.

### Testing Subscriptions Locally (Xcode StoreKit)

Xcode's StoreKit Configuration lets you simulate purchases **locally in the simulator** without an App Store Connect account or sandbox tester. This is **only for development/testing** — it has no effect on production builds.

#### One-time setup

The StoreKit config file must be created inside Xcode (hand-authored JSON won't work reliably):

1. Open the Xcode workspace:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. **File → New → File** (⌘N) → search for **StoreKit** → select **StoreKit Configuration File** → **Next**.
3. Name it `MonyxProducts`, set Group to `Runner`, ensure the target is checked → **Create**.
4. In the visual editor, click **+** → **Add Auto-Renewable Subscription**:
   - **Group name**: `Monyx Pro`
   - **Reference Name**: `Monyx Pro Monthly`
   - **Product ID**: `monyx_pro_monthly_3` ← must match exactly
   - **Price**: `2.99`
   - **Duration**: `1 Month`
   - Add a display name/description in the Localization section.
5. Set the scheme to use it: **Product → Scheme → Edit Scheme** (⌘⇧<) → **Run → Options** → **StoreKit Configuration** → select `MonyxProducts.storekit`.

#### Running with StoreKit

**Important:** `flutter run` does not apply Xcode scheme settings. To test IAP you must launch from Xcode:

1. First, generate the dart-define config (only needed when `.env` changes):
   ```bash
   flutter run --dart-define-from-file=.env
   ```
   Then stop the app (`q`).
2. In Xcode, press **⌘R** to build and run. Xcode applies the StoreKit config at launch.
3. In the app, tap the FAB (profile button) → tap the **★ Upgrade to Pro** banner → tap **Subscribe**.
4. Xcode's StoreKit test environment handles the purchase immediately — no Apple ID needed.
5. The app should hide the banner ad and unlock unlimited profiles.

For everything else (map, ballistics, ads), `flutter run --dart-define-from-file=.env` works fine.

#### Manage test transactions

In Xcode: **Debug → StoreKit → Manage Transactions**. From here you can:

- **Approve / decline** pending transactions
- **Refund** a purchase (test the downgrade flow)
- **Delete** all transactions (reset to free tier)
- **Force renewal** to simulate a subscription renewing

#### Expire or cancel

In the transaction manager, select the subscription and click **Cancel Subscription** or **Request Refund** to test what happens when a user downgrades.

> **Note:** The `.storekit` file is only for local testing. It has no secrets and no effect on production. Real subscriptions are managed entirely in App Store Connect.

## Animal Track Identification

Pro subscribers can identify animal species from photos of tracks (footprints and scat) directly on-device — no internet required.

### How it works

1. Tap the **paw-print button** on the map screen (Pro only — free users see a locked icon with an upgrade prompt).
2. Choose the trace type: **Footprint** 🐾 or **Scat** 💩.
3. The camera opens — photograph the track.
4. Monyx runs a YOLOv11 object-detection model on-device to identify the species.
5. A **full-screen results page** shows the photo with bounding boxes drawn over detected tracks, plus a ranked list of species predictions with confidence scores.
6. Results can be **saved** to local storage and **retrieved** later from the saved tracks list.

### Models

The feature uses [AnimalClue](https://dahlian00.github.io/AnimalCluePage/) (ICCV 2025) YOLOv11n models, converted to TFLite for on-device inference:

| Model     | Species | Input       | Size   | Source                                                                          |
| --------- | ------- | ----------- | ------ | ------------------------------------------------------------------------------- |
| Footprint | 117     | 640×640 RGB | ~10 MB | [risashinoda/footprint_yolo](https://huggingface.co/risashinoda/footprint_yolo) |
| Feces     | 101     | 640×640 RGB | ~10 MB | [risashinoda/feces_yolo](https://huggingface.co/risashinoda/feces_yolo)         |

Both models are bundled in the app binary under `assets/models/`. Total added size is ~20 MB.

### Inference pipeline

1. **Capture** — `image_picker` opens the camera and returns a JPEG.
2. **Preprocess** — Image is resized to 640×640 and converted to a float32 NHWC tensor `[1, 640, 640, 3]` with pixel values normalised to `[0, 1]`.
3. **Infer** — `tflite_flutter` runs the model, producing `[1, C, 8400]` where `C = 4 + num_classes`.
4. **Post-process** — Confidence thresholding (0.25), coordinate scaling back to original image dimensions, and Non-Maximum Suppression (IoU 0.45) to remove duplicate boxes.
5. **Display** — Bounding boxes are drawn on the photo with colour-coded confidence (green ≥70%, amber ≥40%, red below). Species names and confidence percentages are shown.

### Model export

The TFLite models are generated from the original PyTorch weights using a Python pipeline in `tools/`. See [tools/README.md](tools/README.md) for full reproduction instructions.

```bash
python3 -m venv tools/.venv
source tools/.venv/bin/activate
pip install -r tools/requirements.txt
python tools/export_models.py
```

### Architecture

| Component   | File                                       | Role                                                         |
| ----------- | ------------------------------------------ | ------------------------------------------------------------ |
| Detector    | `lib/services/track_detector.dart`         | Loads TFLite model, runs inference, returns `Detection` list |
| Persistence | `lib/services/track_service.dart`          | Saves/loads track results + images via Hive                  |
| State       | `lib/blocs/track_cubit.dart`               | Manages capture → detect → save flow                         |
| Results UI  | `lib/screens/track_result_screen.dart`     | Annotated image + ranked species list                        |
| Saved list  | `lib/screens/saved_tracks_screen.dart`     | Browse and revisit past identifications                      |
| Overlay     | `lib/widgets/detection_image_painter.dart` | Draws bounding boxes on the photo                            |

## Plant Identification

Pro subscribers can identify plant species from photos — entirely on-device, no internet required. Supports US and Canada species.

### How it works

1. Tap the **🌿 button** on the map screen (Pro only).
2. Choose the plant part: **Leaf** 🍃, **Flower** 🌸, **Bark** 🌳, **Fruit** 🍎, or **Whole Plant** 🌿.
3. Take a photo or choose one from gallery.
4. Monyx runs an EfficientNet-Lite0 classifier on-device.
5. Results are **reranked** using your GPS location (US state / Canadian province), current month, and selected plant part.
6. A **results page** shows the photo and a ranked list of species predictions with confidence scores, common names, and scientific names.
7. Results can be **saved** and **retrieved** later.

### Model

| Model | Species | Input       | Size     | Architecture       |
| ----- | ------- | ----------- | -------- | ------------------ |
| Plant | 200–500 | 224×224 RGB | ~5–15 MB | EfficientNet-Lite0 |

The model is trained on iNaturalist research-grade observations filtered to US + Canada plants. See [tools/README.md](tools/README.md) for the full training and export pipeline.

### Phase 2: Metadata Reranking

Raw classifier predictions are reranked using bundled species metadata:

- **Region**: species present in user's state/province get a 1.5× boost; absent species get 0.2×
- **Season**: species visible in the current month get 1.3×; off-season species get 0.5×
- **Plant part**: species with strong identifiers for the selected part get 1.2×

Formula: `finalScore = modelScore × regionWeight × seasonWeight × partWeight`

Region lookup is fully offline — uses a bundled US state / Canadian province bounding-box table.

### Architecture

| Component   | File                                   | Role                                                         |
| ----------- | -------------------------------------- | ------------------------------------------------------------ |
| Classifier  | `lib/services/plant_classifier.dart`   | Loads TFLite model, runs classification, returns predictions |
| Reranker    | `lib/services/plant_reranker.dart`     | Metadata-based reranking (region, season, plant part)        |
| Region      | `lib/services/region_lookup.dart`      | Offline GPS → US state / CA province resolver                |
| Persistence | `lib/services/plant_service.dart`      | Saves/loads plant results + images via Hive                  |
| State       | `lib/blocs/plant_cubit.dart`           | Manages capture → classify → rerank → save flow              |
| Results UI  | `lib/screens/plant_result_screen.dart` | Photo + ranked species list with confidence bars             |
| Saved list  | `lib/screens/saved_plants_screen.dart` | Browse and revisit past identifications                      |
| Metadata    | `lib/models/plant_metadata.dart`       | Species metadata model (regions, months, parts, toxicity)    |
