#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------------------------
# Script information
script_name='HEAD DOWNLOADER - HSAF PRODUCT PRECIPITATION H60/H60B'
script_version="2.8.3"
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
# Allow up to N concurrent script instances (set to 1 for strict single instance)
MAX_INSTANCES=2
SEMAPHORE_TAG="hsaf_h60_downloader"
LOCK_DIR="/share/LOCKS/${SEMAPHORE_TAG}.locks"
mkdir -p "$LOCK_DIR"

# If forced, stop old runs (excluding this PID) and clear stale locks
if $force_run; then
  echo " [SEMAPHORE] Force mode enabled (-f): stopping previous runs and clearing locks..."

  script_base="$(basename "$0")"
  self_pid="$$"
  parent_pid="${PPID:-0}"

  mapfile -t other_pids < <(pgrep -f "$script_base" 2>/dev/null || true)

  for pid in "${other_pids[@]}"; do
    [[ -z "${pid:-}" ]] && continue
    [[ "$pid" -eq "$self_pid" ]] && continue
    [[ "$pid" -eq "$parent_pid" ]] && continue
    if ps -o args= -p "$pid" 2>/dev/null | grep -q "$script_base"; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done

  sleep 1

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
  # Release flock by closing fd (only if we actually acquired a slot)
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
  # Strip CR if the file was edited on Windows
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

# === User settings ======================================================================
# Choose which .netrc entry to use (e.g., "ftphsaf.meteoam.it" or "ftphsaf.meteoam.it_sg")
netrc_machine_label="ftphsaf.meteoam.it"

# Actual FTP host to connect to
ftp_url="ftphsaf.meteoam.it"

# Optional proxy (or empty)
proxy=""

# Mode: 'realtime' or 'history'
script_mode='realtime'
# Days back inclusive (0=today only)
days=2

# Local path pattern
local_folder_raw="/share/HSAF_PRECIPITATION/nrt/h60/%YYYY/%MM/%DD/"

# Pick remote folder template by mode
if [ "$script_mode" == 'realtime' ]; then
  ftp_folder_raw="/products/h60/h60_cur_mon_data/"
else
  ftp_folder_raw="/hsaf_archive/h60/%YYYY/%MM/%DD/%HH/"
fi

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

    # Resolve FTP & local folders
    ftp_folder_def=${ftp_folder_raw/'%YYYY'/$year_get}
    ftp_folder_def=${ftp_folder_def/'%MM'/$month_get}
    ftp_folder_def=${ftp_folder_def/'%DD'/$day_get}
    ftp_folder_def=${ftp_folder_def/'%HH'/$hour_get}

    local_folder_def=${local_folder_raw/'%YYYY'/$year_get}
    local_folder_def=${local_folder_def/'%MM'/$month_get}
    local_folder_def=${local_folder_def/'%DD'/$day_get}
    if [ "$script_mode" == 'realtime' ]; then
      local_folder_def=${local_folder_def/'%HH'/'realtime'}
    else
      local_folder_def=${local_folder_def/'%HH'/$hour_get}
    fi
    mkdir -p "$local_folder_def"

    # Expected quarters
    quarters=(00 15 30 45)
    if [ "$script_mode" == 'realtime' ] && [[ "$date_step" == "$now_day" && "$hour_get" == "$now_hour" ]]; then
      SAFETY_LAG_MIN=5
      adj=$(( (10#$now_min - SAFETY_LAG_MIN) ))
      if (( adj < 0 )); then
        latest_q=-1
      else
        latest_q=$(( adj / 15 ))
        (( latest_q > 3 )) && latest_q=3
      fi
      if (( latest_q < 0 )); then
        echo "  [INFO] No completed quarters yet; go to previous hour."
        echo " ===> HOUR_STEP: $hour_get ===> END "
        continue
      fi
      quarters=( "${quarters[@]:0:$((latest_q+1))}" )
    fi

    # ---- List only this hour on the server --------------------------------------------
    echo "  [INFO] Listing FTP folder for ${ftp_folder_def} (hour ${hour_get}) ..."
    set +e
    ftp_list=$(run_lftp "
      cd ${ftp_folder_def}
      cls -1 h60_${date_step}_${hour_get}??_fdk.nc.gz | sort -r | sed -e 's/@//'
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

    # ---- Expected quarter checks + download (portable: get -c -O <dir>) ---------------
    for q in "${quarters[@]}"; do
      ftp_file="h60_${date_step}_${hour_get}${q}_fdk.nc.gz"
      local_target="${local_folder_def}/${ftp_file}"

      echo -n "  [CHECK] Expected: ${ftp_file} ... "

      if echo "$ftp_list" | grep -q "^${ftp_file}\$"; then
        echo -n "FOUND on FTP  "
        if [[ -e "$local_target" ]]; then
          echo "→ SKIP (already downloaded)"
          continue
        fi
        echo -n "→ downloading ... "
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
      else
        echo "NOT ON FTP (this hour)"
      fi
    done

    echo " ===> HOUR_STEP: $hour_get ===> END "
  done

  echo " ===> TIME_STEP: $date_step ===> END "
done

echo " ==> $script_name (Version: $script_version Release_Date: $script_date)"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="

