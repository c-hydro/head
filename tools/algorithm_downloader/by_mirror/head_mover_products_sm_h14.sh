#!/usr/bin/env bash

python3 <<'EOF'
import os
import re
import shutil
from datetime import datetime

# ================= CONFIG =================

SRC_DIR = "/share/HSAF_MIRROR/h14_cur_mon_grib/"
DST_ROOT = "/share/HSAF_SM/ecmwf/nrt/h14/"

# Filenames like: h14_20251119_0000.grib.bz2
H14_REGEX = re.compile(
    r"^h14_(?P<date>\d{8})_(?P<hour>\d{2})(?P<minute>\d{2})\.grib\.bz2$"
)

# How many days back from today (from YYYYMMDD in filename)
N_DAYS = 3

# =========================================

today = datetime.now().date()

print(f"Syncing h14 for last {N_DAYS} days based on filename date...")
print(f"  Source: {SRC_DIR}")
print(f"  Dest root: {DST_ROOT}")

if not os.path.isdir(SRC_DIR):
    print(f"ERROR: source dir does not exist: {SRC_DIR}")
    raise SystemExit(1)

for fname in sorted(os.listdir(SRC_DIR)):
    m = H14_REGEX.match(fname)
    if not m:
        continue  # skip non-h14 files

    date_str = m.group("date")  # YYYYMMDD
    file_date = datetime.strptime(date_str, "%Y%m%d").date()

    days_ago = (today - file_date).days
    if days_ago < 0 or days_ago >= N_DAYS:
        continue

    src_path = os.path.join(SRC_DIR, fname)

    yyyy = file_date.strftime("%Y")
    mm   = file_date.strftime("%m")
    dd   = file_date.strftime("%d")

    # Destination: /share/HSAF_PRECIPITATION/nrt/h14/YYYY/MM/DD/
    dst_dir = os.path.join(DST_ROOT, yyyy, mm, dd)
    dst_path = os.path.join(dst_dir, fname)

    print(f"\nFile: {fname}")
    print(f"  Date in name: {file_date} (days_ago={days_ago})")
    print(f"  From: {src_path}")
    print(f"  To:   {dst_path}")

    os.makedirs(dst_dir, exist_ok=True)

    if os.path.exists(dst_path):
        print("  → Already exists, skipping.")
        continue

    try:
        shutil.copy2(src_path, dst_path)
        print("  → Copied.")
    except OSError as e:
        print(f"  → ERROR copying: {e}")

print("\nDone.")
EOF

