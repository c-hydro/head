#!/usr/bin/env bash
# Sync HSAF products from mirror to NRT archive for the last N days.
# - Handles daily and hourly products.
# - Uses filename to derive YYYY/MM/DD[/HH] destination structure.

python3 <<'EOF'
import os
import re
import shutil
from datetime import datetime, timedelta

# ============= CONFIGURATION ======================================

N_DAYS = 3  # look back this many days from now (mtime-based)

PRODUCTS = [
    # --- Daily product: h10 [h10_20251118_day_merged.H5.gz] 
    {
        "name": "h10",
        "src_dir": "/share/HSAF_MIRROR/h10_cur_mon_data",
        "dst_dir": "/share/HSAF_SNOW/nrt/h10/",
        # filename: h10_YYYYMMDD_day_merged.H5.gz
        # groups: date (YYYYMMDD)
        "pattern": re.compile(
            r"^h10_(?P<date>\d{8})_day_merged\.H5\.gz$"
        ),
        "has_hour": False,
    },

    # Daily product: h12 [h12_20251118_day_merged.grib2.gz] 
    {
        "name": "h12",
        "src_dir": "/share/HSAF_MIRROR/h12_cur_mon_data",
        "dst_dir": "/share/HSAF_SNOW/nrt/h12/",
        # Example filename: hXX_YYYYMMDDHH_hour_merged.H5.gz
        #   - date: YYYYMMDD
        #   - hour: HH
        "pattern": re.compile(
            r"^h12_(?P<date>\d{8})_day_merged\.grib2\.gz$"
        ),
        "has_hour": False,
    },
    
    # Daily product: h13 [h13_20251118_day_merged.grib2.gz] 
    {
        "name": "h13",
        "src_dir": "/share/HSAF_MIRROR/h13_cur_mon_data",
        "dst_dir": "/share/HSAF_SNOW/nrt/h13/",
        # Example filename: hXX_YYYYMMDDHH_hour_merged.H5.gz
        #   - date: YYYYMMDD
        #   - hour: HH
        "pattern": re.compile(
            r"^h13_(?P<date>\d{8})_day_merged\.grib2\.gz$"
        ),
        "has_hour": False,
    },
    
    # Daily product: h34 [h34_20251118_day_merged.H5.gz] 
    {
        "name": "h34",
        "src_dir": "/share/HSAF_MIRROR/h34_cur_mon_data",
        "dst_dir": "/share/HSAF_SNOW/nrt/h34/",
        # Example filename: hXX_YYYYMMDDHH_hour_merged.H5.gz
        #   - date: YYYYMMDD
        #   - hour: HH
        "pattern": re.compile(
            r"^h34_(?P<date>\d{8})_day_merged\.H5\.gz$"
        ),
        "has_hour": False,
    },
    
]

# ==================================================================

now = datetime.now()
threshold = now - timedelta(days=N_DAYS)

def should_consider(path: str) -> bool:
    """Return True if file mtime is within last N_DAYS."""
    try:
        mtime = datetime.fromtimestamp(os.path.getmtime(path))
    except OSError:
        return False
    return mtime >= threshold

def sync_product(prod_cfg):
    name = prod_cfg["name"]
    src_dir = prod_cfg["src_dir"]
    dst_base = prod_cfg["dst_dir"]
    pattern = prod_cfg["pattern"]
    has_hour = prod_cfg["has_hour"]

    print(f"\n=== Processing product {name} ===")
    if not os.path.isdir(src_dir):
        print(f"  Source directory does not exist: {src_dir}")
        return

    try:
        entries = os.listdir(src_dir)
    except OSError as e:
        print(f"  ERROR listing {src_dir}: {e}")
        return

    for fname in sorted(entries):
        src_path = os.path.join(src_dir, fname)

        # Skip non-files
        if not os.path.isfile(src_path):
            continue

        # Only recent files
        if not should_consider(src_path):
            continue

        m = pattern.match(fname)
        if not m:
            # Not matching the expected template for this product
            continue

        date_str = m.group("date")  # YYYYMMDD
        dt = datetime.strptime(date_str, "%Y%m%d")
        yyyy = f"{dt.year:04d}"
        mm = f"{dt.month:02d}"
        dd = f"{dt.day:02d}"

        if has_hour:
            hour = m.group("hour")  # HH
            dst_dir = os.path.join(dst_base, yyyy, mm, dd, hour)
        else:
            dst_dir = os.path.join(dst_base, yyyy, mm, dd)

        dst_path = os.path.join(dst_dir, fname)

        print(f"  File: {fname}")
        print(f"    → src: {src_path}")
        print(f"    → dst: {dst_path}")

        if not os.path.isdir(dst_dir):
            try:
                os.makedirs(dst_dir, exist_ok=True)
                print(f"    Created dir: {dst_dir}")
            except OSError as e:
                print(f"    ERROR creating {dst_dir}: {e}")
                continue

        if os.path.exists(dst_path):
            print("    Destination already exists, skipping.")
            continue

        try:
            shutil.copy2(src_path, dst_path)
            print("    Copied.")
        except OSError as e:
            print(f"    ERROR copying: {e}")

def main():
    print(f"Starting sync. Now: {now}, threshold: {threshold} (last {N_DAYS} days)")
    for prod in PRODUCTS:
        sync_product(prod)
    print("\nAll done.")

if __name__ == "__main__":
    main()
EOF

