#!/usr/bin/env python3
"""Download one distinct, freely-licensed product photo per stock-list item.

Images are searched through the Openverse API restricted to CC0 / public
domain material so no attribution is required on the storefront.

Rules enforced by this script:
  * one unique image per item (sha256 deduplicated across the whole run),
  * no illustration / clipart / advertisement style results,
  * no re-use of another item's photo - items without a good match simply
    get no image instead of a duplicated one,
  * every file is re-encoded to a consistent JPEG so the grid stays tidy.

Usage:  python3 scripts/fetch_item_images.py [--only 1,2,3]
Writes: priv/static/resources/item-NN-slug.jpg
        reference/item-image-sources.json
"""

import argparse
import hashlib
import io
import json
import os
import re
import pathlib
import sys
import time
import urllib.parse
import urllib.request

from PIL import Image

API = "https://api.openverse.org/v1/images/"
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "priv" / "static" / "resources"
MANIFEST = ROOT / "reference" / "item-image-sources.json"
UA = "RobinahsShopCatalogue/1.0 (image sourcing script)"
MAX_BYTES = 700_000
TARGET_WIDTH = 900
MIN_WIDTH = 420

BAD_WORDS = (
    "illustration", "sticker", "clipart", "clip art", "vector", "drawing",
    "painting", "engraving", "advertisement", "poster", "vintage", "antique",
    "logo", "icon", "watermark", "collage", "sketch", "museum", "sculpture",
    "png", "cartoon", "clip", "wallpaper", "typography", "letterpress",
    "caricature", "diagram", "chart", "map", "screenshot", "mockup",
    # documentary / scene photos that show the word but not the product
    "war", "battle", "soldier", "army", "snow", "panic", "crowd", "protest",
    "pride", "factory", "beer", "wine", "veterinary", "grave", "funeral",
    "beach", "protest", "riot", "disaster", "flood", "drought",
    "polisher", "kneeling", "holy", "tapestry", "sledding", "reed's",
    "curtain", "embroidery", "quilting",
)

BAD_PATTERNS = (
    r"\(\d{4}",          # dated artwork / museum object titles
    r"\d{4}[-–]\d{4}",   # date ranges
    r"\|",               # "title | collection" style museum records
)

# number, slug, queries (tried in order), relevance terms, category
ITEMS = [
    (1, "cup-with-numbers", ["mug with numbers", "coffee mug", "ceramic mug",
                             "drinking cup", "cup"],
     ["mug", "cup"], "Home & Kitchen"),
    (2, "toilet-paper", ["toilet paper", "toilet roll", "tissue paper",
                         "bathroom tissue"],
     ["toilet", "tissue", "roll"], "Household Plastics & Storage"),
    (3, "colgate-herbal-toothpaste", ["herbal toothpaste", "toothpaste tube",
                                      "toothpaste", "toothbrush toothpaste"],
     ["toothpaste"], "Household Plastics & Storage"),
    (4, "nomi-buckets", ["plastic bucket", "utility bucket", "pail bucket",
                         "household bucket"],
     ["bucket", "pail"], "Household Plastics & Storage"),
    (5, "dry-cell-batteries", ["dry cell battery", "batteries", "battery"],
     ["battery"], "Household Plastics & Storage"),
    (6, "torch", ["flashlight", "torch light", "led flashlight"],
     ["flashlight", "torch"], "Household Plastics & Storage"),
    (7, "lato-milk-sachets", ["milk sachet", "milk packet", "milk bottle",
                              "fresh milk"],
     ["milk"], "Home & Kitchen"),
    (8, "ruler", ["ruler", "wooden ruler", "ruler measurement"],
     ["ruler"], "School Essentials"),
    (9, "black-book-quire", ["black notebook", "notebook", "exercise book"],
     ["notebook", "book"], "School Essentials"),
    (10, "mattress-rose-foam", ["mattress", "bed mattress", "memory foam mattress"],
     ["mattress"], "Bedding & Comfort"),
    (11, "butto-one-litre", ["jerrycan", "plastic canister", "water canister",
                             "plastic container", "container plastic"],
     ["canister", "jerrycan", "container", "jerry"],
     "Household Plastics & Storage"),
    (12, "bay-item", ["bay leaves", "dried leaves"], ["bay", "leaf"],
     "Home & Kitchen"),
    (13, "bed-sheets-white", ["white bed sheets", "bed sheet", "bedsheets",
                              "made bed"],
     ["sheet", "bed"], "Bedding & Comfort"),
    (14, "mattress-ecofoam", ["bedroom bed", "bed mattress", "mattress topper"],
     ["bed", "mattress"], "Bedding & Comfort"),
    (15, "baby-patra", ["baby blanket", "baby bedding", "baby towel"],
     ["baby"], "Bedding & Comfort"),
    (16, "rice-half-kg", ["rice grains", "bag of rice", "uncooked rice"],
     ["rice"], "Home & Kitchen"),
    (17, "baby-knicker", ["baby clothes", "baby bodysuit", "baby clothing"],
     ["baby"], "Bedding & Comfort"),
    (18, "butto-half-litre", ["plastic water bottle", "plastic bottle",
                              "water jug", "sports bottle"],
     ["bottle", "jug"], "Household Plastics & Storage"),
    (19, "handkerchief", ["handkerchief", "cotton handkerchief"],
     ["handkerchief", "hanky"], "Bedding & Comfort"),
    (20, "steel-bottle-medium", ["metal bottle", "stainless steel bottle",
                                 "steel water bottle"],
     ["metal bottle", "steel bottle", "stainless"], "Bags & Travel"),
    (21, "relax-bottle", ["plastic water bottle", "drinking bottle", "water bottle"],
     ["bottle"], "Bags & Travel"),
    (22, "vest", ["undershirt", "cotton vest", "white vest", "tank top"],
     ["vest", "shirt", "top"], "Bedding & Comfort"),
    (23, "half-pot-big", ["cooking pot", "saucepan", "stock pot", "kitchen pot"],
     ["pot", "pan"], "Home & Kitchen"),
    (24, "set-mathematical", ["protractor", "geometry compass tool",
                              "geometry set", "mathematics tools"],
     ["protractor", "geometry", "compass", "math"], "School Essentials"),
    (25, "blue-soap", ["blue soap bar", "laundry soap", "soap bar", "soap"],
     ["soap"], "Household Plastics & Storage"),
    (26, "ruler-second", ["ruler measurement", "wooden ruler", "plastic ruler"],
     ["ruler"], "School Essentials"),
    (27, "shoe-polish-kangaroo", ["shoe polish", "leather shoe care",
                                  "polish tin"],
     ["polish", "shoe"], "Household Plastics & Storage"),
    (28, "shoe-brush", ["shoe brush", "cleaning brush", "brushes"],
     ["brush"], "Household Plastics & Storage"),
    (29, "rubber-eraser", ["eraser", "pencil eraser", "rubber eraser"],
     ["eraser", "rubber"], "School Essentials"),
    (30, "geisha-small", ["cooking oil bottle", "vegetable oil", "oil bottle"],
     ["oil"], "Home & Kitchen"),
    (31, "go-back-stocks", ["backpack", "school bag", "rucksack"],
     ["backpack", "bag", "rucksack"], "Bags & Travel"),
    (32, "breakable-bowl-plate", ["ceramic bowl", "dinner plate", "white bowl",
                                  "porcelain bowl"],
     ["bowl", "plate"], "Home & Kitchen"),
    (33, "angel-cup", ["drinking glass", "glass cup", "clear glass"],
     ["glass", "cup"], "Home & Kitchen"),
    (34, "sponge", ["cleaning sponge", "kitchen sponge", "sponge"],
     ["sponge"], "Household Plastics & Storage"),
    (35, "colgate-charcoal-toothpaste", ["charcoal toothpaste", "black toothpaste",
                                         "toothpaste"],
     ["toothpaste", "charcoal"], "Household Plastics & Storage"),
    (36, "vaseline-jar", ["petroleum jelly", "skin cream jar", "moisturizer cream",
                          "hand cream"],
     ["jelly", "petroleum", "cream", "lotion", "moisturizer"],
     "Household Plastics & Storage"),
]

_last_request = [0.0]


def http_get(url, tries=3):
    for attempt in range(tries):
        wait = 3.2 - (time.time() - _last_request[0])
        if wait > 0:
            time.sleep(wait)
        _last_request[0] = time.time()
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=45) as resp:
                return resp.read(), dict(resp.headers)
        except urllib.error.HTTPError as err:
            if err.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                time.sleep(20 if err.code == 429 else 5)
                continue
            return None, {"status": err.code}
        except Exception:
            if attempt < tries - 1:
                time.sleep(5)
                continue
            return None, {"status": 0}
    return None, {"status": 0}


def search(query, sources):
    params = {
        "q": query,
        "page_size": "20",
        "license": "cc0,pdm",
        "source": ",".join(sources),
        "mature": "false",
    }
    body, _ = http_get(API + "?" + urllib.parse.urlencode(params))
    if not body:
        return []
    try:
        return json.loads(body).get("results", [])
    except json.JSONDecodeError:
        return []


def acceptable(result, terms):
    title = (result.get("title") or "").lower()
    if not title or any(bad in title for bad in BAD_WORDS):
        return False
    if any(re.search(pattern, title) for pattern in BAD_PATTERNS):
        return False
    return any(term in title for term in terms)


def score(result, terms, query):
    title = (result.get("title") or "").lower()
    hits = sum(1 for term in terms if term in title)
    phrase = sum(1 for word in query.lower().split() if word in title)
    bonus = 2 if str(result.get("url", "")).lower().endswith((".jpg", ".jpeg")) else 0
    bonus += 1 if result.get("source") == "stocksnap" else 0
    return hits * 3 + phrase * 2 + bonus


def load_used_hashes():
    hashes = set()
    if MANIFEST.exists():
        try:
            for row in json.loads(MANIFEST.read_text()):
                if row.get("sha256"):
                    hashes.add(row["sha256"])
        except (json.JSONDecodeError, AttributeError, TypeError):
            pass
    for path in OUT_DIR.glob("*.jpg"):
        hashes.add(hashlib.sha256(path.read_bytes()).hexdigest())
    for path in OUT_DIR.glob("*.png"):
        hashes.add(hashlib.sha256(path.read_bytes()).hexdigest())
    return hashes


def prepare(data):
    image = Image.open(io.BytesIO(data))
    image.load()
    if image.width < MIN_WIDTH:
        return None, None, None
    if image.mode in ("RGBA", "LA", "P"):
        background = Image.new("RGB", image.size, (255, 255, 255))
        background.paste(image.convert("RGBA"), mask=image.convert("RGBA").split()[-1])
        image = background
    else:
        image = image.convert("RGB")
    if image.width > TARGET_WIDTH:
        height = round(image.height * TARGET_WIDTH / image.width)
        image = image.resize((TARGET_WIDTH, height), Image.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=82, optimize=True)
    payload = buffer.getvalue()
    if len(payload) > MAX_BYTES:
        buffer = io.BytesIO()
        image.save(buffer, "JPEG", quality=70, optimize=True)
        payload = buffer.getvalue()
    if len(payload) > MAX_BYTES:
        return None, None, None
    return payload, image.width, image.height


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="", help="comma separated item numbers")
    args = parser.parse_args()
    only = {int(n) for n in args.only.split(",") if n.strip()} if args.only else None

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    used = load_used_hashes()
    manifest = {}
    if MANIFEST.exists():
        try:
            for row in json.loads(MANIFEST.read_text()):
                manifest[row["number"]] = row
        except (json.JSONDecodeError, KeyError, TypeError):
            pass

    missing = []
    for number, slug, queries, terms, category in ITEMS:
        if only and number not in only:
            continue
        existing = manifest.get(number)
        if existing and (ROOT / "priv" / "static" / existing["file"]).exists() and not only:
            print(f"{number:02d} keep {existing['file']}")
            continue

        candidates = []
        for query in queries:
            for result in search(query, ["stocksnap", "rawpixel"]):
                if acceptable(result, terms):
                    result["_query"] = query
                    result["_score"] = score(result, terms, query)
                    candidates.append(result)
            if candidates:
                break

        candidates.sort(key=lambda item: item["_score"], reverse=True)
        saved = None
        for result in candidates:
            body, _ = http_get(result.get("url", ""))
            if not body:
                continue
            payload, width, height = prepare(body)
            if not payload:
                continue
            digest = hashlib.sha256(payload).hexdigest()
            if digest in used:
                continue
            used.add(digest)
            file_name = f"item-{number:02d}-{slug}.jpg"
            (OUT_DIR / file_name).write_bytes(payload)
            saved = {
                "number": number,
                "item_slug": slug,
                "category": category,
                "file": f"/resources/{file_name}",
                "query": result["_query"],
                "title": result.get("title"),
                "creator": result.get("creator"),
                "source": result.get("source"),
                "license": result.get("license"),
                "landing_url": result.get("foreign_landing_url") or result.get("url"),
                "width": width,
                "height": height,
                "bytes": len(payload),
                "sha256": digest,
            }
            break

        if saved:
            manifest[number] = saved
            print(f"{number:02d} {saved['file']} <- {saved['title']} [{saved['source']}]")
        else:
            manifest.pop(number, None)
            missing.append(number)
            print(f"{number:02d} NO DISTINCT IMAGE FOUND ({slug})")

    ordered = [manifest[n] for n in sorted(manifest)]
    MANIFEST.write_text(json.dumps(ordered, indent=2) + "\n")
    print(f"\nimages: {len(ordered)} / {len(ITEMS)}   missing: {missing}")


if __name__ == "__main__":
    sys.exit(main())
