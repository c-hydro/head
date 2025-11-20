#!/usr/bin/env bash

python3 <<'EOF'
import os
import re
import shutil
from datetime import datetime

# ================= CONFIG =================

SRC_DIR = "/share/HSAF_MIRROR/h26_cur_mon_nc/"
DST_ROOT = "/share/HSAF_SM/ecmwf/nrt/h26"

# Filenames like: h26_2025111900_R01.nc
H26_REGEX = re.compile(
    r"^h26_(?P<date>\d{8})(?P<hour>\d{2})_R01\.nc$"
)

# How many days back from today (from YYYYMMDD in filename)
N_DAYS = 3

# =========================================

today = datetime.now().date()

print(f"Syncing h26 for last {N_DAYS} days based on filename date...")
print(f"  Source: {SRC_DIR}")
print(f"  Dest root: {DST_ROOT}")

if not os.path.isdir(SRC_DIR):
    print(f"ERROR: source dir does not exist: {SRC_DIR}")
    raise SystemExit(1)

for fname in sorted(os.listdir(SRC_DIR)):
    m = H26_REGEX.match(fname)
    if not m:
        continue  # skip non-h26 files

    date_str = m.group("date")  # YYYYMMDD
    file_date = datetime.strptime(date_str, "%Y%m%d").date()

    days_ago = (today - file_date).days
    if days_ago < 0 or days_ago >= N_DAYS:
        continue  # outside time window

    src_path = os.path.join(SRC_DIR, fname)

    yyyy = file_date.strftime("%Y")
    mm   = file_date.strftime("%m")
    dd   = file_date.strftime("%d")

    # Destination: /share/HSAF_PRECIPITATION/nrt/h26/YYYY/MM/DD/
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

