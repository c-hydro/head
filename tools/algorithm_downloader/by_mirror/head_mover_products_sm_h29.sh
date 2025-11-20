#!/usr/bin/env bash

python3 <<'EOF'
import os
import re
import shutil
from datetime import datetime, timedelta
from glob import glob

# ================================================================
#   CONFIGURATION
# ================================================================

SRC_DIR = "/share/HSAF_MIRROR/h29_cur_mon_nc"
DST_DIR = "/share/HSAF_SM/ascat/nrt/h29/"

# your template:
#   "*H29_C_LIIB_YYYYMMDDHH*"
#
# Regex to extract date & hour
FILENAME_REGEX = re.compile(
    r".*H29_C_LIIB_(?P<date>\d{8})(?P<hour>\d{2}).*"
)

N_DAYS = 3  # look back

# ================================================================

now = datetime.now()
time_limit = now - timedelta(days=N_DAYS)

def is_recent(path):
    """Check file mtime."""
    try:
        return datetime.fromtimestamp(os.path.getmtime(path)) >= time_limit
    except:
        return False

print(f"Syncing last {N_DAYS} days of H29 files…")

for offset in range(N_DAYS):
    dt = now - timedelta(days=offset)
    date_step = dt.strftime("%Y%m%d")

    # Pattern: *H122_C_LIIB_YYYYMMDD??*
    pattern = os.path.join(SRC_DIR, f"*H29_C_LIIB_{date_step}" + "??*")

    for src in glob(pattern):
        if not os.path.isfile(src):
            continue
        if not is_recent(src):
            continue

        fname = os.path.basename(src)

        # Extract date & hour
        m = FILENAME_REGEX.match(fname)
        if not m:
            print(f"  Skip (no match): {fname}")
            continue

        date = m.group("date")    # YYYYMMDD
        hour = m.group("hour")    # HH

        # Build target folders YYYY/MM/DD/HH
        d = datetime.strptime(date, "%Y%m%d")
        yyyy = d.strftime("%Y")
        mm   = d.strftime("%m")
        dd   = d.strftime("%d")

        dst_folder = os.path.join(DST_DIR, yyyy, mm, dd, hour)
        dst_path = os.path.join(dst_folder, fname)

        print(f"\nFound: {fname}")
        print(f"   Date: {date}, Hour: {hour}")
        print(f"   From: {src}")
        print(f"   To:   {dst_path}")

        os.makedirs(dst_folder, exist_ok=True)

        if os.path.exists(dst_path):
            print("   Already exists → skip")
            continue

        try:
            shutil.copy2(src, dst_path)
            print("   Copied.")
        except Exception as e:
            print(f"   ERROR: {e}")

print("\nDone.")
EOF

