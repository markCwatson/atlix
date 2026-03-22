"""
Download and curate a plant image dataset from iNaturalist for US + Canada species.

Creates an ImageFolder dataset structure:
  data/plants/train/<species_name>/image_001.jpg
  data/plants/val/<species_name>/image_001.jpg

Also outputs plant_classes.json mapping class indices to scientific names.

Usage:
  python tools/build_plant_dataset.py [--species 300] [--images-per-species 100]

Requires: pip install pyinaturalist requests pillow
"""

import argparse
import json
import os
import random
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# Target species list: common US/Canada plants relevant to hunters/outdoors.
# This list can be expanded — the script also supplements from iNaturalist's
# most-observed species if more are needed to reach the target count.
PRIORITY_SPECIES = [
    # Trees
    "Acer saccharum",  # Sugar Maple
    "Acer rubrum",  # Red Maple
    "Quercus alba",  # White Oak
    "Quercus rubra",  # Red Oak
    "Pinus strobus",  # Eastern White Pine
    "Pinus ponderosa",  # Ponderosa Pine
    "Picea glauca",  # White Spruce
    "Picea mariana",  # Black Spruce
    "Abies balsamea",  # Balsam Fir
    "Tsuga canadensis",  # Eastern Hemlock
    "Betula papyrifera",  # Paper Birch
    "Betula alleghaniensis",  # Yellow Birch
    "Fagus grandifolia",  # American Beech
    "Fraxinus americana",  # White Ash
    "Populus tremuloides",  # Quaking Aspen
    "Thuja occidentalis",  # Eastern White Cedar
    "Juniperus virginiana",  # Eastern Red Cedar
    "Larix laricina",  # Tamarack
    "Prunus serotina",  # Black Cherry
    "Tilia americana",  # American Basswood
    "Ulmus americana",  # American Elm
    "Carya ovata",  # Shagbark Hickory
    "Juglans nigra",  # Black Walnut
    "Platanus occidentalis",  # American Sycamore
    "Liriodendron tulipifera",  # Tulip Tree
    "Pseudotsuga menziesii",  # Douglas Fir
    "Sequoia sempervirens",  # Coast Redwood
    # Shrubs
    "Cornus sericea",  # Red Osier Dogwood
    "Sambucus nigra",  # Elderberry
    "Viburnum opulus",  # Highbush Cranberry
    "Rhus typhina",  # Staghorn Sumac
    "Alnus incana",  # Grey Alder
    "Salix discolor",  # Pussy Willow
    "Kalmia latifolia",  # Mountain Laurel
    "Rhododendron maximum",  # Rosebay Rhododendron
    "Ilex verticillata",  # Winterberry
    # Berries
    "Rubus idaeus",  # Red Raspberry
    "Rubus allegheniensis",  # Allegheny Blackberry
    "Vaccinium corymbosum",  # Highbush Blueberry
    "Vaccinium myrtilloides",  # Velvetleaf Blueberry
    "Gaultheria procumbens",  # Wintergreen
    "Mitchella repens",  # Partridgeberry
    # Toxic plants (important for safety awareness)
    "Toxicodendron radicans",  # Poison Ivy
    "Toxicodendron vernix",  # Poison Sumac
    "Conium maculatum",  # Poison Hemlock
    "Cicuta maculata",  # Water Hemlock
    "Atropa belladonna",  # Deadly Nightshade
    "Datura stramonium",  # Jimsonweed
    "Phytolacca americana",  # Pokeweed
    "Actaea pachypoda",  # White Baneberry
    "Arisaema triphyllum",  # Jack-in-the-Pulpit
    # Common ground cover / wildflowers
    "Trifolium repens",  # White Clover
    "Taraxacum officinale",  # Dandelion
    "Plantago major",  # Common Plantain
    "Solidago canadensis",  # Canada Goldenrod
    "Asclepias syriaca",  # Common Milkweed
    "Impatiens capensis",  # Jewelweed
    "Trillium grandiflorum",  # White Trillium
    "Maianthemum canadense",  # Canada Mayflower
    "Cypripedium acaule",  # Pink Lady's Slipper
    "Equisetum arvense",  # Field Horsetail
    # Ferns
    "Osmunda cinnamomea",  # Cinnamon Fern
    "Polystichum acrostichoides",  # Christmas Fern
    "Pteridium aquilinum",  # Bracken Fern
    "Dryopteris marginalis",  # Marginal Wood Fern
]


def fetch_species_observations(species_name, target=400, place_ids="6712,97394"):
    """
    Fetch observation photos for a species from iNaturalist API.
    Paginates automatically to collect up to `target` photo URLs.
    place_ids: 6712 = Canada, 97394 = United States
    """
    try:
        import requests
    except ImportError:
        print("Installing requests...")
        os.system(f"{sys.executable} -m pip install requests")
        import requests

    api_url = "https://api.inaturalist.org/v1/observations"
    photo_urls = []
    page = 1
    per_page = 200  # iNaturalist max per page

    while len(photo_urls) < target:
        params = {
            "taxon_name": species_name,
            "place_id": place_ids,
            "quality_grade": "research",
            "photos": "true",
            "per_page": per_page,
            "page": page,
            "order": "desc",
            "order_by": "votes",
        }

        resp = requests.get(api_url, params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])
        if not results:
            break

        for obs in results:
            for photo in obs.get("photos", []):
                url = photo.get("url", "")
                if url:
                    photo_urls.append(url.replace("square", "medium"))

        page += 1
        # Stop if we've exhausted results
        if len(results) < per_page:
            break

    return photo_urls[:target]


def download_image(url, dest_path):
    """Download a single image, return True on success."""
    try:
        import requests
    except ImportError:
        os.system(f"{sys.executable} -m pip install requests")
        import requests

    try:
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
        content_type = resp.headers.get("content-type", "")
        if "image" not in content_type:
            return False
        with open(dest_path, "wb") as f:
            f.write(resp.content)
        return True
    except Exception:
        return False


def download_top_species(target_count, place_ids="6712,97394"):
    """Fetch the most-observed plant species from iNaturalist for US+Canada."""
    try:
        import requests
    except ImportError:
        os.system(f"{sys.executable} -m pip install requests")
        import requests

    url = "https://api.inaturalist.org/v1/observations/species_counts"
    params = {
        "iconic_taxa": "Plantae",
        "place_id": place_ids,
        "quality_grade": "research",
        "per_page": target_count,
    }

    resp = requests.get(url, params=params, timeout=30)
    resp.raise_for_status()
    data = resp.json()

    species = []
    for result in data.get("results", []):
        taxon = result.get("taxon", {})
        name = taxon.get("name")
        rank = taxon.get("rank")
        if name and rank == "species":
            species.append(name)

    return species


def main():
    parser = argparse.ArgumentParser(description="Build plant classification dataset")
    parser.add_argument(
        "--species",
        type=int,
        default=300,
        help="Target number of species (default: 300)",
    )
    parser.add_argument(
        "--images-per-species",
        type=int,
        default=400,
        help="Max images per species (default: 400)",
    )
    parser.add_argument(
        "--val-split",
        type=float,
        default=0.2,
        help="Validation split ratio (default: 0.2)",
    )
    parser.add_argument(
        "--min-images",
        type=int,
        default=30,
        help="Skip species with fewer images than this (default: 30)",
    )
    args = parser.parse_args()

    out_dir = Path(__file__).parent.parent / "data" / "plants"
    train_dir = out_dir / "train"
    val_dir = out_dir / "val"
    assets_dir = Path(__file__).parent.parent / "assets" / "models"

    # Build species list: priority species + iNaturalist top species
    species_list = list(PRIORITY_SPECIES)
    if len(species_list) < args.species:
        print(f"Fetching top {args.species} observed species from iNaturalist...")
        top_species = download_top_species(args.species * 2)
        for s in top_species:
            if s not in species_list:
                species_list.append(s)
            if len(species_list) >= args.species:
                break

    print(
        f"\nTarget: {len(species_list)} species, {args.images_per_species} images each"
    )
    print(f"Output: {out_dir}\n")

    class_map = {}
    class_idx = 0
    skipped = 0

    for i, species in enumerate(species_list):
        safe_name = species.lower().replace(" ", "_")
        print(f"[{i+1}/{len(species_list)}] {species}...", end=" ", flush=True)

        # Skip already-downloaded species
        species_train = train_dir / safe_name
        species_val = val_dir / safe_name
        existing_count = 0
        if species_train.exists():
            existing_count += len(list(species_train.glob("*.jpg")))
        if species_val.exists():
            existing_count += len(list(species_val.glob("*.jpg")))
        if existing_count >= args.images_per_species * 0.8:
            class_map[class_idx] = species
            class_idx += 1
            print(f"CACHED ({existing_count} images)")
            continue

        # Fetch photo URLs
        try:
            urls = fetch_species_observations(species, target=args.images_per_species)
        except Exception as e:
            print(f"SKIP (fetch error: {e})")
            skipped += 1
            continue

        if len(urls) < args.min_images:
            print(f"SKIP ({len(urls)} images < {args.min_images} minimum)")
            skipped += 1
            continue

        # Create directories
        species_train = train_dir / safe_name
        species_val = val_dir / safe_name
        species_train.mkdir(parents=True, exist_ok=True)
        species_val.mkdir(parents=True, exist_ok=True)

        # Download images concurrently
        random.shuffle(urls)
        urls = urls[: args.images_per_species]
        val_count = max(1, int(len(urls) * args.val_split))
        val_urls = urls[:val_count]
        train_urls = urls[val_count:]

        tasks = []
        for j, url in enumerate(train_urls):
            dest = species_train / f"{safe_name}_{j:04d}.jpg"
            tasks.append((url, dest))
        for j, url in enumerate(val_urls):
            dest = species_val / f"{safe_name}_{j:04d}.jpg"
            tasks.append((url, dest))

        downloaded = 0
        with ThreadPoolExecutor(max_workers=10) as pool:
            futures = {pool.submit(download_image, u, d): d for u, d in tasks}
            for fut in as_completed(futures):
                if fut.result():
                    downloaded += 1

        if downloaded < args.min_images:
            print(f"SKIP (only {downloaded} downloaded)")
            # Clean up
            import shutil

            shutil.rmtree(species_train, ignore_errors=True)
            shutil.rmtree(species_val, ignore_errors=True)
            skipped += 1
            continue

        class_map[class_idx] = species
        class_idx += 1
        print(f"OK ({downloaded} images)")

    # Save class mapping
    assets_dir.mkdir(parents=True, exist_ok=True)
    class_file = assets_dir / "plant_classes.json"
    with open(class_file, "w") as f:
        json.dump(class_map, f, indent=2)

    print(f"\n{'='*60}")
    print(f"Dataset complete: {class_idx} species, {skipped} skipped")
    print(f"Classes saved to: {class_file}")
    print(f"Training data: {train_dir}")
    print(f"Validation data: {val_dir}")


if __name__ == "__main__":
    main()
