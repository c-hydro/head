#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------------------------
# Script information
script_name='HEAD DOWNLOADER - HSAF SOIL MOISTURE H29 (ASCAT METOP A/B/C) - REALTIME'
script_version="1.0.0"
script_date='2025/10/24'

# ========================================================================================
# Parse arguments (currently: -f/--force)
force_run=false
for arg in "$@"; do
  case "$arg" in
    -f|--force) force_run=true ;;
    *) ;;
  esac
done

# === Concurrency settings ===============================================================
MAX_INSTANCES=2
SEMAPHORE_TAG="hsaf_h29_downloader"
LOCK_DIR="/tmp/${SEMAPHORE_TAG}.locks"
mkdir -p "$LOCK_DIR"

# If forced, stop old runs (excluding this PID) and clear stale locks
if $force_run; then
  echo " [SEMAPHORE] Force mode enabled (-f): stopping previous runs and clearing locks..."

  script_base="$(basename "$0")"
  self_pid="$$"
  parent_pid="${PPID:-0}"

  mapfile -t other_pids < <(pgrep -f "$script_base" 2>/dev/null || true)

  # TERM others first
  for pid in "${other_pids[@]}"; do
    [[ -z "${pid:-}" ]] && continue
    [[ "$pid" -eq "$self_pid" ]] && continue
    [[ "$pid" -eq "$parent_pid" ]] && continue
    if ps -o args= -p "$pid" 2>/dev/null | grep -q "$script_base"; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  sleep 1
  # KILL stubborn ones
  for pid in "${other_pids[@]}"; do
    [[ -z "${pid:-}" ]] && continue
    [[ "$pid" -eq "$self_pid" ]] && continue
    [[ "$pid" -eq "$parent_pid" ]] && continue
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done

  rm -f "${LOCK_DIR}"/slot.*.lock 2>/dev/null || true
fi

SLOT_ACQUIRED=""
LOCK_FD=""
for i in $(seq 1 "$MAX_INSTANCES"); do
  exec {fd}> "${LOCK_DIR}/slot.${i}.lock"
  if flock -n "$fd"; then
    SLOT_ACQUIRED="$i"
    LOCK_FD="$fd"
    break
  else
    eval "exec ${fd}>&-"
  fi
done

if [[ -z "${SLOT_ACQUIRED}" ]]; then
  echo " [SEMAPHORE] Max instances (${MAX_INSTANCES}) already running."
  if $force_run; then
    echo " [SEMAPHORE] Force flag active — continuing anyway without a slot."
  else
    echo " [SEMAPHORE] Use -f to override and force a run."
    exit 0
  fi
fi

cleanup() {
  if [[ -n "${LOCK_FD:-}" ]]; then
    eval "exec ${LOCK_FD}>&-"
  fi
}
trap cleanup EXIT INT TERM

# === LFTP runtime safety ================================================================
TIMEOUT_LFTP_SECS=600
LFTP_COMMON_SETTINGS=$(cat <<'EOF'
set cmd:fail-exit yes;
set net:timeout 30;
set net:max-retries 3;
set net:reconnect-interval-base 5;
set net:reconnect-interval-max 20;
set ftp:passive-mode yes;
set xfer:clobber on;
EOF
)

run_lftp() {
  local lftp_body="$1"
  timeout --preserve-status "${TIMEOUT_LFTP_SECS}" bash -c \
  "lftp <<'LFTP_EOF'
set ftp:proxy ${proxy}
${LFTP_COMMON_SETTINGS}
open -u ${ftp_usr},${ftp_pwd} ${ftp_url}
${lftp_body}
close
quit
LFTP_EOF"
}

# === Credential loader from ~/.netrc by machine label ===================================
# Usage: load_netrc_creds <machine_label>
# Sets: ftp_usr, ftp_pwd
load_netrc_creds() {
  local label="$1"
  local netrc_file="${HOME}/.netrc"
  if [[ ! -f "$netrc_file" ]]; then
    echo " [ERROR] ${netrc_file} not found; create it and chmod 600." >&2
    exit 1
  fi
  local out
  # Strip CR if edited on Windows
  if ! out=$(tr -d '\r' < "$netrc_file" | awk -v M="$label" '
    $1=="machine" { in_section = ($2==M); next }
    in_section && $1=="login"    { login=$2 }
    in_section && $1=="password" { password=$2 }
    END{
      if (login!="" && password!="") { print login "\t" password; exit 0 }
      else exit 1
    }
  '); then
    echo " [ERROR] No credentials found in ~/.netrc for machine \""$label"\"." >&2
    echo -n " [HINT] Available machine labels: "
    tr -d '\r' < "$netrc_file" | awk '$1=="machine"{printf "%s ", $2} END{print ""}'
    exit 1
  fi
  ftp_usr="${out%%$'\t'*}"
  ftp_pwd="${out#*$'\t'}"
}

# === User settings (H29) ================================================================
# .netrc machine label to use (e.g., "ftphsaf.meteoam.it" or "..._sg")
netrc_machine_label="ftphsaf.meteoam.it"
# Actual FTP host
ftp_url="ftphsaf.meteoam.it"
# Optional proxy (or empty)
proxy=""

# Mode: 'realtime' or 'history'
script_mode='realtime'
# Days back inclusive (0=today only)
days=7

# Local path pattern (H29)
local_folder_raw="/share/HSAF_SM/ascat/nrt/h29/%YYYY/%MM/%DD/%HH/"

# Remote folder template (H29)
if [ "$script_mode" == 'realtime' ]; then
  ftp_folder_raw="/products/h29/h29_cur_mon_nc/"
else
  # adjust if your archive path differs
  ftp_folder_raw="/products/h29_test/h29_cur_mon_nc/"
fi

# If you want to skip the *current* hour when too fresh (files still writing), set a lag:
SAFETY_LAG_MIN=5   # minutes; applies only to current hour in realtime

# ----------------------------------------------------------------------------------------
# Anchors for realtime logic
time_now=$(date '+%Y-%m-%d')
now_day=$(date +%Y%m%d)
now_hour=$(date +%H)
now_min=$(date +%M)

echo " ==================================================================================="
echo " ==> $script_name (Version: $script_version Release_Date: $script_date)"
echo " ==> START ..."
if [[ -n "${SLOT_ACQUIRED}" ]]; then
  echo " ==> Concurrency slot acquired: ${SLOT_ACQUIRED}/${MAX_INSTANCES}"
else
  echo " ==> Concurrency slot: forced (no slot acquired)"
fi

# Load credentials
ftp_usr=""
ftp_pwd=""
load_netrc_creds "$netrc_machine_label"
echo " ===> INFO MACHINE -- URL: ${ftp_url} -- NETRC: ${netrc_machine_label} -- USER: ${ftp_usr}"

# ----------------------------------------------------------------------------------------
for day in $(seq 0 "$days"); do
  # Target date (local TZ)
  date_step=$(date -d "${time_now} -${day} days" +%Y%m%d)
  echo " ===> TIME_STEP: $date_step ===> START "

  # UTC path components
  year_get=$(date -u -d "$date_step" +"%Y")
  month_get=$(date -u -d "$date_step" +"%m")
  day_get=$(date -u -d "$date_step" +"%d")

  # Decide hour range for this date
  if [ "$script_mode" == 'realtime' ]; then
    if [[ "$date_step" == "$now_day" ]]; then
      count_start=$((10#$now_hour))  # current hour (decimal)
      count_end=0
    else
      count_start=23
      count_end=0
    fi
  else
    count_start=23
    count_end=0
  fi

  # Descend hours (… HH, HH-1, …, 00)
  for hour in $(seq ${count_start} -1 ${count_end}); do
    hour_get=$(printf "%02d" ${hour})
    echo " ===> HOUR_STEP: $hour_get ===> START "

    # If realtime & current hour is too fresh, skip (safety lag)
    if [ "$script_mode" == 'realtime' ] && [[ "$date_step" == "$now_day" && "$hour_get" == "$now_hour" ]]; then
      adj=$(( (10#$now_min - SAFETY_LAG_MIN) ))
      if (( adj < 0 )); then
        echo "  [INFO] Current hour within safety lag (${SAFETY_LAG_MIN}m). Skipping to previous hour."
        echo " ===> HOUR_STEP: $hour_get ===> END "
        continue
      fi
    fi

    # Resolve FTP & local folders
    ftp_folder_def=${ftp_folder_raw/'%YYYY'/$year_get}
    ftp_folder_def=${ftp_folder_def/'%MM'/$month_get}
    ftp_folder_def=${ftp_folder_def/'%DD'/$day_get}
    ftp_folder_def=${ftp_folder_def/'%HH'/$hour_get}

    local_folder_def=${local_folder_raw/'%YYYY'/$year_get}
    local_folder_def=${local_folder_def/'%MM'/$month_get}
    local_folder_def=${local_folder_def/'%DD'/$day_get}
    local_folder_def=${local_folder_def/'%HH'/$hour_get}
    mkdir -p "$local_folder_def"

    # H29 filenames: *H29_C_LIIB_YYYYMMDDHHMMSS_YYYYMMDDhhmmss_YYYYMMDDhhmmss____.nc
    # We group by the **processing timestamp hour** (first datetime after C_LIIB_)
    # Mask for this hour:
    list_mask="*H29_C_LIIB_${date_step}${hour_get}*"
    # Stricter alternative if needed:
    # list_mask="*H29_C_LIIB_${date_step}${hour_get}??????_*____.nc"

    echo "  [INFO] Listing FTP folder for ${ftp_folder_def} (mask ${list_mask}) ..."
    set +e
    ftp_list=$(run_lftp "
      cd ${ftp_folder_def}
      cls -1 ${list_mask} | sort -r | sed -e 's/@//'
    ")
    list_rc=$?
    set -e

    if [[ $list_rc -ne 0 ]]; then
      echo "  [WARN] FTP list failed for hour ${hour_get} (rc=$list_rc). Going to previous hour."
      echo " ===> HOUR_STEP: $hour_get ===> END "
      continue
    fi

    if [[ -z "${ftp_list//[[:space:]]/}" ]]; then
      echo "  [WARN] No files published on FTP for ${date_step} hour ${hour_get}. Going to previous hour."
      echo " ===> HOUR_STEP: $hour_get ===> END "
      continue
    fi

    # Download every file in the list (H29 produces many per hour)
    echo "  [INFO] Found $(echo "$ftp_list" | wc -l) file(s) on FTP for this hour."
    while IFS= read -r ftp_file; do
      [[ -z "$ftp_file" ]] && continue
      local_target="${local_folder_def}/${ftp_file}"

      echo -n "  [FILE] ${ftp_file} ... "
      if [[ -e "$local_target" ]]; then
        echo "SKIP (already downloaded)"
        continue
      fi

      echo -n "downloading ... "
      set +e
      run_lftp "
        cd ${ftp_folder_def}
        get -c -O ${local_folder_def} ${ftp_file}
      " >/dev/null
      dl_rc=$?
      set -e

      if [[ $dl_rc -eq 0 ]]; then
        echo "DONE"
      elif [[ $dl_rc -eq 124 ]]; then
        echo "TIMEOUT"
        [[ -f "$local_target" ]] && rm -f "$local_target"
      else
        echo "FAILED (rc=$dl_rc)"
        [[ -f "$local_target" ]] && rm -f "$local_target"
      fi
    done <<< "$ftp_list"

    echo " ===> HOUR_STEP: $hour_get ===> END "
  done

  echo " ===> TIME_STEP: $date_step ===> END "
done

echo " ==> $script_name (Version: $script_version Release_Date: $script_date)"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="

