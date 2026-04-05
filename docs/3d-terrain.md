# 3D Terrain

A 2D/3D toggle on the map screen lets the user switch to a tilted 3D view with real terrain elevation. In 3D mode, a vertical slider controls elevation exaggeration — amplifying hills and mountains for better visual relief.

## How it works

1. Tap the **terrain button** (🏔) on the right sidebar to enter 3D mode.
2. The map tilts to 60° pitch, terrain relief appears, and an atmospheric sky layer renders behind the map.
3. A **vertical slider** appears above the sidebar buttons — drag it to adjust elevation exaggeration from 1.0× (true scale) to 10.0× (dramatic relief).
4. In 3D mode, two-finger tilt gestures let you freely adjust the camera pitch.
5. Tap the terrain button again to return to flat 2D — the camera animates back to 0° pitch.

## Free vs Pro

| Capability          | Free | Pro |
| ------------------- | ---- | --- |
| 3D terrain toggle   | ✅   | ✅  |
| Exaggeration slider | ✅   | ✅  |

3D terrain is available to all users — it uses Mapbox's built-in terrain DEM tiles at no additional cost.

## Mapbox terrain pipeline

The feature uses three Mapbox style primitives:

1. **RasterDemSource** — `mapbox://mapbox.mapbox-terrain-dem-v1` (514 px tiles). Provides elevation data (RGB-encoded DEM) that the renderer uses to deform the map surface.
2. **Terrain** — set via `setStyleTerrain({"source": "mapbox-dem", "exaggeration": N})`. The `exaggeration` parameter scales elevation values — 1.0 is true-to-life, higher values amplify vertical relief.
3. **SkyLayer** — `SkyType.ATMOSPHERE` with simulated sun position. Renders a blue atmosphere dome behind all other layers, visible when the camera is pitched.

### Enable flow

```
addSource(RasterDemSource)  →  setStyleTerrain({source, exaggeration})
                             →  addLayer(SkyLayer)
                             →  flyTo(pitch: 60°)
```

### Disable flow

```
setStyleTerrain('')         →  removeStyleLayer(sky)
                             →  removeStyleSource(dem)
                             →  flyTo(pitch: 0°)
```

### Live exaggeration update

The slider calls `setStyleTerrainProperty('exaggeration', value)` on each change — the terrain re-renders in real time with no source/layer teardown.

## Exaggeration range

| Value | Effect                                        |
| ----: | --------------------------------------------- |
|  1.0× | True-to-life elevation (subtle in flat areas) |
|  1.5× | Default — gentle amplification                |
|  3.0× | Pronounced hills, clear ridge lines           |
| 10.0× | Maximum — dramatic mountain relief            |

## Overlay compatibility

All existing overlays (wind particles, bullet arc, pellet spray, spread cone, lethal range circle, compass, land boundaries) continue to render correctly in 3D mode. They use screen-space projection via `MapboxMap.pixelForCoordinate()` and are unaffected by camera pitch.

## Offline considerations

The `RasterDemSource` fetches DEM tiles from Mapbox servers. These are **not** included in offline tile region downloads by default. In offline mode with no DEM tiles cached, terrain degrades gracefully to flat — no crash, just no elevation relief. A future enhancement could add DEM tiles to the `TileRegionLoadOptions` for offline regions.

## Architecture

| Component | File                              | Role                                               |
| --------- | --------------------------------- | -------------------------------------------------- |
| Extension | `lib/screens/map/_terrain.dart`   | Enable/disable 3D, exaggeration slider, FAB button |
| State     | `lib/screens/map/map_screen.dart` | `_is3DEnabled`, `_elevationExaggeration` variables |
