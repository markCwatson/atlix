# Hunting Setback Overlay

Red "no-hunt zone" overlay showing areas within the provincial setback distance of buildings. Hunters must stay outside these zones when discharging firearms.

## How it works

1. Tap the **shield button** on the map sidebar (Pro only).
2. On first use, a disclaimer dialog appears — tap "I Understand" to proceed.
3. Semi-transparent red polygons appear on the map showing the setback zones around every building.
4. Tap the shield button again to turn the overlay off.

The overlay can be used alongside the land overlay — enable both to see Crown/public land _and_ setback zones at the same time.

## Regulations (POC: Nova Scotia)

| Rule             | Distance       | Source          |
| ---------------- | -------------- | --------------- |
| Dwelling setback | 201 m (660 ft) | NS Wildlife Act |
| Applies to       | All firearms   | —               |

Nova Scotia uses a single 201 m setback distance for all firearm types. There is no weapon-specific differentiation (unlike some provinces).

## Data source

Building footprints come from the **Microsoft Canadian Building Footprints** dataset:

- **Coverage:** All Canadian provinces and territories (11.8M buildings total)
- **Nova Scotia:** 402,358 building footprints
- **Format:** GeoJSON polygons, EPSG:4326
- **License:** Open Data Commons Open Database License (ODbL)
- **Source:** [github.com/microsoft/CanadianBuildingFootprints](https://github.com/microsoft/CanadianBuildingFootprints)

The footprints are ML-derived from satellite imagery (ResNet34 segmentation + polygonization). Precision is 98.7%, false positive ratio < 0.5%.

## Data pipeline

The tileset is built offline using `tools/build_setback_tileset.py`. Three steps:

```
download → process → tiles
```

### Prerequisites

```bash
brew install gdal tippecanoe
source tools/.venv/bin/activate
pip install -r tools/land_requirements.txt    # geopandas, shapely, pyproj, requests
```

### Usage

```bash
# Run all three steps:
python tools/build_setback_tileset.py all

# Or individually:
python tools/build_setback_tileset.py download
python tools/build_setback_tileset.py process
python tools/build_setback_tileset.py tiles
```

### Step 1: Download

Downloads the Microsoft Building Footprints zip for Nova Scotia and extracts the GeoJSON:

- URL: `https://minedbuildings.z5.web.core.windows.net/legacy/canadian-buildings-v2/NovaScotia.zip`
- Output: `tools/land_data/raw/ns_buildings.geojson` (~81 MB, 402k polygons)

### Step 2: Process

Buffers every building polygon by 201 m and dissolves into a single multipolygon:

1. Load GeoJSON into GeoPandas
2. Reproject WGS84 → UTM zone 20N (EPSG:32620) for accurate metric buffering
3. Buffer each polygon by 201 m
4. Dissolve in chunks of 50,000 features (manages memory for large datasets)
5. Merge chunks with `unary_union`
6. Simplify with 5 m tolerance (reduces vertex count, no visible impact at target zoom)
7. Reproject back to WGS84 (EPSG:4326)
8. Export with properties: `zone_type`, `setback_m`, `province_state`

Output: `tools/land_data/processed/ns_setback_201m.geojson` (~22 MB)

### Step 3: Tiles

Runs tippecanoe to generate a vector tileset:

```bash
tippecanoe -o ns_setback_overlay.mbtiles \
  -Z 4 -z 14 \
  -l setback_zone \
  --drop-densest-as-needed \
  --extend-zooms-if-still-dropping \
  --coalesce-densest-as-needed \
  --force \
  ns_setback_201m.geojson
```

- Zoom range 4–14
- Layer name `setback_zone` (referenced in Flutter code)
- Output: `tools/land_data/output/ns_setback_overlay.mbtiles` (~12 MB)

### After generating tiles

1. Go to [Mapbox Studio Tilesets](https://studio.mapbox.com/tilesets/)
2. Click **New tileset** → upload `ns_setback_overlay.mbtiles`
3. Copy the tileset ID (e.g., `yourusername.ns_setback_overlay`)
4. Add to `.env`: `SETBACK_TILESET_ID=yourusername.ns_setback_overlay`

## Flutter implementation

The overlay is implemented in `lib/screens/map/_setback_overlay.dart` as an extension on `_MapScreenState`, following the same pattern as the land overlay.

### Rendering

- **VectorSource** points to `mapbox://{setbackTilesetId}`
- **FillLayer** — red (#C62828) at 25% opacity for semi-transparent zone fill
- **LineLayer** — red (#D32F2F) at 60% opacity, 1 px width for zone boundaries
- Static colours (single zone type, no data-driven match expression needed)

### Disclaimer

On first toggle, an AlertDialog warns the user that zones are approximate. The dismissal is persisted in Hive (`settings` box, key `setback_disclaimer_accepted`) so it only shows once.

### Offline support

When the user downloads an offline region, the setback tileset is included alongside the base map and land overlay tiles. Configured in `offline_region_service.dart`.

## Free vs Pro

| Capability                          | Free | Pro |
| ----------------------------------- | ---- | --- |
| Setback overlay toggle              | —    | ✅  |
| Offline download with setback tiles | —    | ✅  |

## Architecture

| Component       | File                                       | Role                                                       |
| --------------- | ------------------------------------------ | ---------------------------------------------------------- |
| Config          | `lib/config.dart`                          | `AppConfig.setbackTilesetId` from `--dart-define` / `.env` |
| Map overlay     | `lib/screens/map/_setback_overlay.dart`    | VectorSource + FillLayer + LineLayer, toggle, disclaimer   |
| Map screen      | `lib/screens/map/map_screen.dart`          | `_setbackOverlayEnabled` state, shield button in sidebar   |
| Offline regions | `lib/services/offline_region_service.dart` | Includes setback tileset in offline downloads              |
| Data pipeline   | `tools/build_setback_tileset.py`           | Download → buffer + dissolve → tippecanoe → MBTiles        |
| Python deps     | `tools/land_requirements.txt`              | geopandas, shapely, pyproj, requests                       |

## Expanding to other provinces

The pipeline is designed for province-by-province expansion. To add a province:

1. Add an entry to `PROVINCE_CONFIGS` in `build_setback_tileset.py` with the province's zip name, UTM EPSG code, and setback distance
2. Run the pipeline for that province
3. Merge the outputs or upload as separate tilesets

Province-specific considerations:

| Province | Setback                             | Notes                                  |
| -------- | ----------------------------------- | -------------------------------------- |
| NS       | 201 m (all firearms)                | Implemented                            |
| ON       | 400 m (rifle/shotgun), 75 m (bow)   | Would need weapon-type-specific layers |
| AB       | 183 m (600 ft, all firearms)        | Similar to NS                          |
| BC       | 100 m (all firearms near dwellings) | Shorter distance                       |

For provinces with weapon-specific setbacks, the pipeline could generate multiple buffer distances and the Flutter overlay could add a filter tied to the active weapon profile.

## Disclaimer

Setback zones are approximate and for reference only. GPS accuracy, building data vintage, and new construction mean the overlay may not reflect current conditions. Always verify compliance with local hunting regulations.
