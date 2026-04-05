#!/usr/bin/env python3
"""
Download building footprints, buffer by the provincial setback distance,
dissolve into a single "no-hunt zone" layer, and generate a Mapbox-compatible
vector tileset (MBTiles).

PROOF-OF-CONCEPT: Nova Scotia only (201 m setback for all firearms).

Data source:
    Microsoft Canadian Building Footprints (ODbL license)
    https://github.com/microsoft/CanadianBuildingFootprints

Prerequisites:
    brew install gdal tippecanoe
    source tools/.venv/bin/activate
    pip install -r tools/land_requirements.txt

Usage:
    python tools/build_setback_tileset.py download   # fetch building footprints
    python tools/build_setback_tileset.py process    # buffer + dissolve
    python tools/build_setback_tileset.py tiles      # tippecanoe → MBTiles
    python tools/build_setback_tileset.py all        # run all steps

Output:
    tools/land_data/output/ns_setback_overlay.mbtiles — upload to Mapbox Studio
"""

from __future__ import annotations

import json
import subprocess
import sys
import zipfile
from pathlib import Path

# ─── Paths ──────────────────────────────────────────────────────────────
TOOLS_DIR = Path(__file__).parent
LAND_DIR = TOOLS_DIR / "land_data"
RAW_DIR = LAND_DIR / "raw"
PROCESSED_DIR = LAND_DIR / "processed"
OUTPUT_DIR = LAND_DIR / "output"

# ─── Data source ────────────────────────────────────────────────────────
# Microsoft Canadian Building Footprints — per-province zip of GeoJSON
MS_BUILDINGS_BASE = (
    "https://minedbuildings.z5.web.core.windows.net" "/legacy/canadian-buildings-v2"
)

# Province configs: (download_name, UTM EPSG for accurate buffering, setback_m)
PROVINCE_CONFIGS: dict[str, dict] = {
    "NS": {
        "zip_name": "NovaScotia",
        "utm_epsg": 32620,  # UTM zone 20N — covers Nova Scotia
        "setback_m": 201,  # NS Wildlife Act: 201 m (660 ft) for all firearms
    },
}

# ─── Helpers ────────────────────────────────────────────────────────────


def ensure_dirs() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


# ─── Step 1: Download ──────────────────────────────────────────────────


def download(province: str = "NS") -> None:
    """Download and extract Microsoft Building Footprints for a province."""
    ensure_dirs()

    try:
        import requests
    except ImportError:
        sys.exit("Missing 'requests'. Run: pip install -r tools/land_requirements.txt")

    cfg = PROVINCE_CONFIGS.get(province)
    if cfg is None:
        sys.exit(f"Unknown province: {province}. Available: {list(PROVINCE_CONFIGS)}")

    zip_name = cfg["zip_name"]
    geojson_out = RAW_DIR / f"{province.lower()}_buildings.geojson"

    if geojson_out.exists():
        size_mb = geojson_out.stat().st_size / (1 << 20)
        print(f"Buildings already downloaded: {geojson_out} ({size_mb:.0f} MB)")
        return

    zip_url = f"{MS_BUILDINGS_BASE}/{zip_name}.zip"
    zip_path = RAW_DIR / f"{zip_name}.zip"

    # Download zip
    if not zip_path.exists():
        print(f"Downloading {zip_name} building footprints...")
        print(f"  URL: {zip_url}")
        resp = requests.get(
            zip_url,
            headers={"User-Agent": "Mozilla/5.0 (Atlix Hunt setback pipeline)"},
            timeout=300,
            stream=True,
        )
        resp.raise_for_status()
        total = int(resp.headers.get("content-length", 0))
        downloaded = 0
        with open(zip_path, "wb") as f:
            for chunk in resp.iter_content(chunk_size=1 << 20):
                f.write(chunk)
                downloaded += len(chunk)
                if total > 0:
                    pct = downloaded * 100 // total
                    print(f"\r  {downloaded >> 20} / {total >> 20} MB ({pct}%)", end="")
        print()
        print(f"  Saved: {zip_path} ({zip_path.stat().st_size >> 20} MB)")
    else:
        print(f"Zip already exists: {zip_path}")

    # Extract GeoJSON from zip
    print(f"Extracting GeoJSON from {zip_path.name}...")
    with zipfile.ZipFile(zip_path, "r") as zf:
        # The zip contains one .geojson file (name varies)
        geojson_names = [n for n in zf.namelist() if n.endswith(".geojson")]
        if not geojson_names:
            sys.exit(f"No .geojson file found in {zip_path}")
        inner_name = geojson_names[0]
        with zf.open(inner_name) as src, open(geojson_out, "wb") as dst:
            while True:
                buf = src.read(1 << 20)
                if not buf:
                    break
                dst.write(buf)

    size_mb = geojson_out.stat().st_size / (1 << 20)
    print(f"  Extracted: {geojson_out} ({size_mb:.0f} MB)")

    # Clean up zip to save disk space
    zip_path.unlink()
    print(f"  Removed zip: {zip_path.name}")
    print("\nDownload complete.")


# ─── Step 2: Process ───────────────────────────────────────────────────


def process(province: str = "NS") -> None:
    """Buffer buildings by setback distance and dissolve into a single layer."""
    ensure_dirs()

    try:
        import geopandas as gpd
        from shapely.ops import unary_union
    except ImportError:
        sys.exit(
            "Missing geopandas/shapely. Run: pip install -r tools/land_requirements.txt"
        )

    cfg = PROVINCE_CONFIGS[province]
    setback_m = cfg["setback_m"]
    utm_epsg = cfg["utm_epsg"]

    buildings_path = RAW_DIR / f"{province.lower()}_buildings.geojson"
    output_path = PROCESSED_DIR / f"{province.lower()}_setback_{setback_m}m.geojson"

    if not buildings_path.exists():
        sys.exit(
            f"Missing {buildings_path}. "
            f"Run: python tools/build_setback_tileset.py download"
        )

    if output_path.exists():
        size_mb = output_path.stat().st_size / (1 << 20)
        print(f"Setback GeoJSON already exists: {output_path} ({size_mb:.0f} MB)")
        return

    # Load buildings
    print(f"Loading {buildings_path.name}...")
    gdf = gpd.read_file(buildings_path)
    print(f"  {len(gdf)} building footprints loaded")

    # Reproject to UTM for accurate metric buffering
    print(f"  Reprojecting to EPSG:{utm_epsg} (UTM)...")
    gdf = gdf.to_crs(epsg=utm_epsg)

    # Buffer each building by setback distance
    print(f"  Buffering by {setback_m} m...")
    gdf["geometry"] = gdf.geometry.buffer(setback_m, resolution=8)

    # Dissolve all buffers into a single geometry.
    # Process in chunks to manage memory for large datasets.
    chunk_size = 50_000
    n = len(gdf)
    if n > chunk_size:
        print(f"  Dissolving in chunks of {chunk_size}...")
        chunks = []
        for start in range(0, n, chunk_size):
            end = min(start + chunk_size, n)
            print(f"    Chunk {start}–{end}...")
            chunk_union = unary_union(gdf.geometry.iloc[start:end])
            chunks.append(chunk_union)
        print("  Merging chunks...")
        dissolved = unary_union(chunks)
    else:
        print("  Dissolving...")
        dissolved = unary_union(gdf.geometry)

    # Simplify to reduce vertex count (~5 m tolerance at UTM scale)
    print("  Simplifying (5 m tolerance)...")
    dissolved = dissolved.simplify(5.0, preserve_topology=True)

    # Build output GeoDataFrame
    result = gpd.GeoDataFrame(
        [
            {
                "zone_type": "setback",
                "setback_m": setback_m,
                "province_state": province,
            }
        ],
        geometry=[dissolved],
        crs=f"EPSG:{utm_epsg}",
    )

    # Reproject back to WGS84
    print("  Reprojecting to EPSG:4326...")
    result = result.to_crs(epsg=4326)

    # Export
    print(f"  Writing {output_path.name}...")
    result.to_file(output_path, driver="GeoJSON")
    size_mb = output_path.stat().st_size / (1 << 20)
    print(f"  Output: {output_path} ({size_mb:.1f} MB)")
    print("\nProcess complete.")


# ─── Step 3: Generate tiles ────────────────────────────────────────────


def tiles(province: str = "NS") -> None:
    """Run tippecanoe to generate vector MBTiles from the setback GeoJSON."""
    ensure_dirs()

    cfg = PROVINCE_CONFIGS[province]
    setback_m = cfg["setback_m"]

    merged = PROCESSED_DIR / f"{province.lower()}_setback_{setback_m}m.geojson"
    if not merged.exists():
        sys.exit(
            f"Missing {merged}. " f"Run: python tools/build_setback_tileset.py process"
        )

    output = OUTPUT_DIR / f"{province.lower()}_setback_overlay.mbtiles"

    # Check tippecanoe is installed
    try:
        subprocess.run(["tippecanoe", "--version"], capture_output=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        sys.exit(
            "tippecanoe is required but not found.\n"
            "Install: brew install tippecanoe  (macOS)"
        )

    cmd = [
        "tippecanoe",
        "-o",
        str(output),
        "-Z",
        "4",  # min zoom
        "-z",
        "14",  # max zoom
        "-l",
        "setback_zone",  # layer name (referenced in Flutter code)
        "--drop-densest-as-needed",
        "--extend-zooms-if-still-dropping",
        "--coalesce-densest-as-needed",
        "--force",  # overwrite existing output
        "-n",
        f"Setback Overlay ({province} {setback_m}m)",
        "-A",
        "Microsoft Building Footprints (ODbL)",
        str(merged),
    ]

    print("Generating vector tiles with tippecanoe...")
    print(f"  $ {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"STDERR: {result.stderr}")
        sys.exit("tippecanoe failed")
    print(result.stderr)  # tippecanoe prints stats to stderr

    size_mb = output.stat().st_size / (1 << 20)
    print(f"\nOutput: {output} ({size_mb:.1f} MB)")
    print(
        "\nNext steps:\n"
        "  1. Upload to Mapbox Studio: https://studio.mapbox.com/tilesets/\n"
        "  2. Click 'New tileset' → upload the .mbtiles file\n"
        "  3. Copy the tileset ID (e.g., yourusername.ns_setback_overlay)\n"
        "  4. Add to .env: SETBACK_TILESET_ID=yourusername.ns_setback_overlay\n"
    )


# ─── CLI ────────────────────────────────────────────────────────────────


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in (
        "download",
        "process",
        "tiles",
        "all",
    ):
        print(
            "Usage: python tools/build_setback_tileset.py <command>\n"
            "\n"
            "Commands:\n"
            "  download  — Download Microsoft Building Footprints\n"
            "  process   — Buffer by setback distance + dissolve\n"
            "  tiles     — Generate MBTiles with tippecanoe\n"
            "  all       — Run all steps in order"
        )
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd in ("download", "all"):
        download()
    if cmd in ("process", "all"):
        process()
    if cmd in ("tiles", "all"):
        tiles()


if __name__ == "__main__":
    main()
