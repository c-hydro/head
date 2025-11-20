#!/bin/bash

#######################################
#  FLAGS
#######################################
FORCE_LOCK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE_LOCK=1
      ;;
    *)
      echo "Unknown option: $1"
      ;;
  esac
  shift
done

#######################################
#  FTP CONFIG
#######################################

# .netrc machine label (must match entry in ~/.netrc)
NETRC_MACHINE_LABEL="ftphsaf.meteoam.it"
FTP_URL="ftphsaf.meteoam.it"

# Days back
DAYS_BACK=3

# Local storage base
LOCAL_FOLDER_MIRROR="/share/HSAF_MIRROR/"

#######################################
#  CONCURRENCY LIMIT (3x)
#######################################
LOCK_DIR="/share/LOCK"
LOCK_BASENAME="head_downloader_products_precipitation_conn_"
MAX_SLOTS=3    # <-- change here if you want more/less
ACQUIRED_LOCK=""

mkdir -p "$LOCK_DIR"

acquire_lock() {
  for i in $(seq 1 "$MAX_SLOTS"); do
    lockfile="${LOCK_DIR}/${LOCK_BASENAME}${i}"

    # If lock exists and FORCE_LOCK is set, remove it
    if [[ -f "$lockfile" && "$FORCE_LOCK" -eq 1 ]]; then
      echo "Forcing removal of stale lock: $lockfile"
      rm -f "$lockfile"
    fi

    # If lock still exists (and we didn't force it), skip this slot
    [[ -f "$lockfile" ]] && continue

    # Try to create the lock atomically
    if ( set -o noclobber; : > "$lockfile" ) 2>/dev/null; then
      echo "$$" > "$lockfile"   # store PID for debugging (optional)
      ACQUIRED_LOCK="$lockfile"
      echo "Acquired slot $i using $lockfile"
      return 0
    fi
  done

  echo "All $MAX_SLOTS slots are currently in use. Exiting."
  exit 1
}

release_lock() {
  if [[ -n "$ACQUIRED_LOCK" ]]; then
    rm -f "$ACQUIRED_LOCK"
    echo "Released slot ($ACQUIRED_LOCK)"
  fi
}

# Ensure the lock is always released
trap release_lock EXIT INT TERM

# Try to take one of the slots
acquire_lock

# =========================
#  ORIGINAL SCRIPT BELOW
# =========================

# Remote folder templates
FTP_FOLDER_H60="/products/h60/h60_cur_mon_data/"
FTP_FOLDER_H61="/products/h61/h61_cur_mon_data/"
FTP_FOLDER_H64="/products/h64/h64_cur_mon_data/"

REMOTE_FOLDERS=(
  "$FTP_FOLDER_H60"
  "$FTP_FOLDER_H61"
  "$FTP_FOLDER_H64"
)

echo "================================================================"
echo "  HSAF FTP MIRROR - PRODUCTS PRECIPITATION - START"
echo "  Timestamp: $(date +"%Y-%m-%d %H:%M:%S")"
echo "  Days back: $DAYS_BACK"
echo "================================================================"
echo

lftp "$FTP_URL" <<EOF
set net:timeout 30
set net:max-retries 5
set net:reconnect-interval-base 5
set ssl:verify-certificate no

set mirror:parallel-transfer-count 4
set mirror:use-pget-n 4

$(for rf in "${REMOTE_FOLDERS[@]}"; do
    name=$(basename "$rf")
    local_dir="${LOCAL_FOLDER_MIRROR%/}/$name"

    # Create local folder if missing (local, not lftp)
    mkdir -p "$local_dir"

    start_ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "echo ================================================================="
    echo "echo PRODUCT: $name"
    echo "echo Remote: $rf"
    echo "echo Local : $local_dir"
    echo "echo Start : $start_ts"
    echo "echo -----------------------------------------------------------------"

    echo "mirror --newer-than=${DAYS_BACK}d --only-newer --continue --no-empty-dirs --verbose \"$rf\" \"$local_dir\""

    end_ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "echo End   : $end_ts"
    echo "echo PRODUCT DONE: $name"
    echo "echo ================================================================="
done)

quit
EOF

echo
echo "================================================================"
echo "  HSAF FTP MIRROR - PRODUCTS PRECIPITATION - END"
echo "  Timestamp: $(date +"%Y-%m-%d %H:%M:%S")"
echo "================================================================"

