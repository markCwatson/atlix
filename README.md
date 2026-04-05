# Atlix Hunt

Offline-first hunting map + ballistics calculator for iOS and Android. Drop a pin, get scope corrections — using your rifle profile, real weather, and terrain elevation. Everything runs on-device.

## Features

| Feature | Free | Pro ($4.99/mo) |
| --- | --- | --- |
| Mapbox satellite/topo map + GPS | ✅ | ✅ |
| Rifle profiles + ballistic solver | 1 profile | Unlimited |
| Shotgun profiles + pattern estimation | 1 profile | Unlimited |
| Manual wind entry for ballistics | ✅ | ✅ |
| Live wind + animated particle overlay | — | ✅ |
| Animal track/scat ID (YOLOv11) | — | ✅ |
| Plant ID (EfficientNet-Lite0) | — | ✅ |
| GPS hike tracking (background) | — | ✅ |
| Public/Crown land overlay | — | ✅ |
| Offline map downloads | — | ✅ |
| Banner ads | Shown | Hidden |

## Tech Stack

| Layer | Tech |
| --- | --- |
| UI | Flutter (iOS + Android), single codebase |
| Maps | Mapbox Maps Flutter SDK (offline support) |
| State | BLoC / Cubit (`flutter_bloc`) |
| Local storage | Hive (NoSQL) |
| GPS | `geolocator` (foreground + background) |
| Weather / Elevation | Open-Meteo API (free, no key) |
| Rifle ballistics | Custom Dart 3-DoF RK4 solver (port of pyballistic) |
| Shotgun patterns | Rayleigh distribution model + OpenCV calibration |
| ML inference | `tflite_flutter` (YOLOv11n + EfficientNet-Lite0) |
| Ads | Google AdMob (banner, adaptive) |
| IAP | `in_app_purchase` (StoreKit / Google Play) |

Bundle ID: `dev.markcwatson.atlix`

## Dev Environment Setup (macOS)

### Prerequisites

- **Flutter SDK** (stable channel, 3.41+)
- **Xcode** with iOS Simulator installed
- **Android Studio** with Android SDK 36+
- **CocoaPods** (`brew install cocoapods`)
- **CMake** (`brew install cmake`) — required by `opencv_dart` / `dartcv4` to compile OpenCV from source during the native build
- **Mapbox account** with two tokens (see below)

> **CMake note:** `dartcv4` uses a Dart native-assets build hook that invokes CMake. Xcode's restricted build environment may not include `/opt/homebrew/bin` in its PATH. If the build fails with `Failed to find cmake version: latest`, symlink it:
>
> ```bash
> sudo ln -sf /opt/homebrew/bin/cmake /usr/local/bin/cmake
> ```
>
> The first build after adding `opencv_dart` compiles OpenCV from source and takes several minutes. Subsequent builds use the cached artifacts.

### 1. Clone and install dependencies

```bash
git clone <repo-url> && cd atlix
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
flutter test                                    # All tests
flutter test test/ballistics_test.dart          # Ballistics solver tests only
flutter test test/pattern_engine_test.dart      # Shotgun pattern engine tests only
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

### Android SDK note

Flutter 3.41+ requires Android SDK 36. If `flutter doctor` complains:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager "platforms;android-36" "build-tools;36.0.0"
```

## Technical Docs

Detailed documentation for each feature is in the [`docs/`](docs/) folder:

- **[docs/rifles.md](docs/rifles.md)** — Ballistic engine: 3-DoF RK4 solver, CIPM-2007 atmosphere, G1/G7 drag, test data
- **[docs/shotguns.md](docs/shotguns.md)** — Pattern estimation: Rayleigh model, PE tables, modifiers, OpenCV calibration pipeline, effective range
- **[docs/weather.md](docs/weather.md)** — Wind overlay: particle system, Open-Meteo API, manual/live/forecast modes, saved profiles
- **[docs/land-overlay.md](docs/land-overlay.md)** — Public/Crown land: data pipeline (CPCAD + provincial open data → tippecanoe → Mapbox), colour-coded map layers, filtering
- **[docs/setback-overlay.md](docs/setback-overlay.md)** — Hunting setback zones: building footprint buffer pipeline (Microsoft Building Footprints → GeoPandas → tippecanoe → Mapbox), red no-hunt overlay
- **[docs/track-id.md](docs/track-id.md)** — Animal track ID: YOLOv11n TFLite models (117 footprint + 101 feces species), inference pipeline
- **[docs/plant-id.md](docs/plant-id.md)** — Plant ID: EfficientNet-Lite0 classifier, metadata reranking (region/season/part)
- **[docs/hike-tracking.md](docs/hike-tracking.md)** — GPS hike tracking: background location, haversine filtering, elevation gain/loss
- **[docs/monetisation.md](docs/monetisation.md)** — Ads (AdMob) & subscription (IAP): product IDs, StoreKit testing, transaction management
- **[docs/ios-tflite.md](docs/ios-tflite.md)** — TFLite iOS symbol stripping workaround (KeepTfLiteSymbols.m + build settings)
- **[docs/deployment.md](docs/deployment.md)** — App Store Connect: build, upload, TestFlight, submission

## What the POC deliberately skips

- No backend / no auth / no sync
- No MIL output (inches + MOA + clicks only)
- No shot history
- Imperial units only
