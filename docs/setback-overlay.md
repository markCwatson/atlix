# Hunting Setback Overlay

Two-zone overlay showing areas where firearm discharge is restricted near buildings. Colour-coded by weapon type so hunters can see at a glance which zones apply to them.

## How it works

1. Tap the **shield button** on the map sidebar (Pro only).
2. On first use, a disclaimer dialog appears — tap "I Understand" to proceed.
3. Two coloured zones appear around every building:
   - **Red** (0–182 m) — all weapons restricted
   - **Yellow** (182–402 m) — rifle/slug restricted (shotgun with shot and bows are OK)
4. A **legend** appears on the map explaining the colour coding.
5. Tap the shield button again to turn the overlay off.

The overlay can be used alongside the land overlay — enable both to see Crown/public land _and_ setback zones at the same time.

## Regulations (Nova Scotia)

Source: [Firearm and Bow Regulations, N.S. Reg. 144/1989](https://novascotia.ca/just/regulations/regs/wifire.htm) (amended to N.S. Reg. 23/2026), made under the _Wildlife Act_, R.S.N.S. 1989, c. 504.

| Section | Distance | Restriction                                                                          | Map colour         |
| ------- | -------- | ------------------------------------------------------------------------------------ | ------------------ |
| s.11(4) | 182 m    | No person shall hunt wildlife within 182 m of any dwelling                           | Red                |
| s.11(3) | 182 m    | No discharge of shotgun (with shot), crossbow, or bow within 182 m of dwelling       | Red                |
| s.11(2) | 402 m    | No discharge of rifle cartridge, single projectile, or slug within 402 m of dwelling | Yellow             |
| s.11(1) | 804 m    | No discharge of any weapon within 804 m of a school                                  | Not shown (future) |

**Key definitions:**

- "dwelling" (s.2(2)): any building kept, used, or occupied as a permanent, seasonal, or temporary residence
- s.11(5): Owner/occupier of a dwelling is exempt from s.11(2)/(3) restrictions
- s.11(6): Exception for dispatching wounded wildlife

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

Buffers every building polygon at two distances and produces concentric zone rings:

1. Load GeoJSON into GeoPandas
2. Reproject WGS84 → UTM zone 20N (EPSG:32620) for accurate metric buffering
3. Buffer all buildings by 182 m → dissolve → inner zone (`zone_type: all_weapons`)
4. Buffer all buildings by 402 m → dissolve → subtract 182 m geometry → outer ring (`zone_type: rifle_slug`)
5. Simplify both zones with 5 m tolerance (reduces vertex count, no visible impact at target zoom)
6. Reproject back to WGS84 (EPSG:4326)
7. Export both zones (with `zone_type`, `distance_m`, `province_state` properties) to a single GeoJSON

Output: `tools/land_data/processed/ns_setback_zones.geojson`

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
  ns_setback_zones.geojson
```

- Zoom range 4–14
- Layer name `setback_zone` (referenced in Flutter code)
- Both zone features (`all_weapons` + `rifle_slug`) end up in the same layer; Flutter filters by `zone_type`
- Output: `tools/land_data/output/ns_setback_overlay.mbtiles`

### After generating tiles

1. Go to [Mapbox Studio Tilesets](https://studio.mapbox.com/tilesets/)
2. Click **New tileset** → upload `ns_setback_overlay.mbtiles`
3. Copy the tileset ID (e.g., `yourusername.ns_setback_overlay`)
4. Add to `.env`: `SETBACK_TILESET_ID=yourusername.ns_setback_overlay`

## Flutter implementation

The overlay is implemented in `lib/screens/map/_setback_overlay.dart` as an extension on `_MapScreenState`, following the same pattern as the land overlay.

### Rendering

- **VectorSource** points to `mapbox://{setbackTilesetId}`
- Two **FillLayers** filtered by `zone_type`:
  - `all_weapons` → red (#C62828) at 25% opacity
  - `rifle_slug` → amber (#FFA000) at 20% opacity
- Two **LineLayers** with matching colours for zone boundaries
- Filters applied via `setStyleLayerProperty('filter', ['==', ['get', 'zone_type'], '...'])`

### Legend

When the overlay is active, a compact legend appears on the map (bottom-left):

- Red swatch — "All weapons (< 182 m)"
- Yellow swatch — "Rifle / slug (182–402 m)"

Built as `_setbackLegend()` in the overlay extension, rendered via a `Positioned` widget in the map `Stack`.

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

| Province | Setback                                         | Notes                                  |
| -------- | ----------------------------------------------- | -------------------------------------- |
| NS       | 182 m (all), 402 m (rifle/slug), 804 m (school) | Implemented (two-zone)                 |
| ON       | 400 m (rifle/shotgun), 75 m (bow)               | Would need weapon-type-specific layers |
| AB       | 183 m (600 ft, all firearms)                    | Single zone                            |
| BC       | 100 m (all firearms near dwellings)             | Shorter distance                       |

For provinces with weapon-specific setbacks, the pipeline could generate multiple buffer distances and the Flutter overlay could add a filter tied to the active weapon profile.

## Disclaimer

Setback zones are approximate and for reference only. GPS accuracy, building data vintage, and new construction mean the overlay may not reflect current conditions. Always verify compliance with local hunting regulations.
