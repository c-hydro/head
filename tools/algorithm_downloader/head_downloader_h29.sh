#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------------------------
# Script information
script_name='HEAD DOWNLOADER - HSAF SOIL MOISTURE H29 (ASCAT METOP A/B/C) - REALTIME'
script_version="1.2.0"
script_date='2025/11/11'

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
SEMAPHORE_TAG="hsaf_h29_downloader"
LOCK_DIR="/share/LOCKS/${SEMAPHORE_TAG}.locks"
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
# set cmd:trace yes;
EOF
)

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

# === User settings (H122) ===============================================================
# .netrc machine label to use (e.g., "ftphsaf.meteoam.it" or "..._sg")
netrc_machine_label="ftphsaf.meteoam.it"
# Actual FTP host
ftp_url="ftphsaf.meteoam.it"
# Optional proxy (or empty)
proxy=""

# Mode: 'realtime' or 'history'
script_mode='realtime'
# Days back inclusive (0=today only)
days=1

# Local path pattern (H122)
local_folder_raw="/share/HSAF_SM/ascat/nrt/h29/%YYYY/%MM/%DD/%HH/"

# Remote folder template (H122)
if [ "$script_mode" == 'realtime' ]; then
  ftp_folder_raw="/products/h29/h29_cur_mon_nc/"
else
  # adjust if your archive path differs
  ftp_folder_raw="/products/h29_test/h29_cur_mon_nc/"
fi

# If you want to skip the *current* hour when too fresh (files still writing), set a lag:
SAFETY_LAG_MIN=5   # minutes; applies only to current hour in realtime

# ---- Per-file status toggle ------------------------------------------------------------
# false = keep single-session mget flow (fast, per-hour status)
# true  = per-file get with explicit SUCCESS/FAIL (one short connection per file)
PER_FILE_LOG=true

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
# Build a single LFTP script with all transfers (used only when PER_FILE_LOG=false)
LFTP_SCRIPT=""
per_file_attempts=0   # counts files attempted in per-file mode
added_cmds=0          # counts hour-level cmds added to LFTP_SCRIPT (single-session mode)

# Base settings + connection (kept at the top of the script we’ll run once)
LFTP_SCRIPT+=$'\n'"set ftp:proxy ${proxy};"
LFTP_SCRIPT+=$'\n'"${LFTP_COMMON_SETTINGS}"
LFTP_SCRIPT+=$'\n'"open -u ${ftp_usr},${ftp_pwd} ${ftp_url};"

# Iterate over days/hours and either:
#  - append to LFTP_SCRIPT (single-session), or
#  - run per-file transfers directly (per-file mode)
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

  for hour in $(seq ${count_start} -1 ${count_end}); do
    hour_get=$(printf "%02d" ${hour})
    echo " ===> HOUR_STEP: $hour_get ===> START "

    # Realtime current-hour safety lag
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

    # Mask for the processing timestamp hour
    list_mask="*H29_C_LIIB_${date_step}${hour_get}*"

    if [ "${PER_FILE_LOG}" != "true" ]; then
      # ---- Original single-session, per-hour status (fast) ----
      LFTP_SCRIPT+=$'\n'"echo ===== [${date_step} ${hour_get}] begin =====;"
      LFTP_SCRIPT+=$'\n'"cd ${ftp_folder_def};"
      LFTP_SCRIPT+=$'\n'"lcd ${local_folder_def};"
      LFTP_SCRIPT+=$'\n'"echo SRC: ${ftp_url}${ftp_folder_def};"
      LFTP_SCRIPT+=$'\n'"echo DST: ${local_folder_def};"
      LFTP_SCRIPT+=$'\n'"mget -c ${list_mask} && echo STATUS: SUCCESS [${date_step} ${hour_get}] || echo STATUS: FAIL [${date_step} ${hour_get}];"
      LFTP_SCRIPT+=$'\n'"echo ===== [${date_step} ${hour_get}] end =====;"
      added_cmds=$((added_cmds+1))
    else
      # ---- Per-file logging mode (exact SRC/DST/file + SUCCESS/FAIL) ----
      echo "----- [${date_step} ${hour_get}] listing files: mask='${list_mask}'"
      # 1) List files for this hour (remote) and capture into bash array
      set +e
      mapfile -t file_list < <(
        lftp -u "${ftp_usr},${ftp_pwd}" "${ftp_url}" <<LFTP_LIST
${LFTP_COMMON_SETTINGS}
set ftp:proxy ${proxy};
open ${ftp_url}
cd ${ftp_folder_def}
cls -1 ${list_mask}
quit
LFTP_LIST
      )
      list_rc=$?
      set -e

      if [[ $list_rc -ne 0 ]]; then
        echo "SRC: ${ftp_url}${ftp_folder_def}"
        echo "DST: ${local_folder_def}"
        echo "STATUS: LIST_FAIL [${date_step} ${hour_get}] (rc=${list_rc})"
        echo "----- [${date_step} ${hour_get}] end (list failed)"
        echo " ===> HOUR_STEP: $hour_get ===> END "
        continue
      fi

      # If no files, print and continue
      if [ "${#file_list[@]}" -eq 0 ] || { [ "${#file_list[@]}" -eq 1 ] && [ -z "${file_list[0]// /}" ]; }; then
        echo "SRC: ${ftp_url}${ftp_folder_def}"
        echo "DST: ${local_folder_def}"
        echo "STATUS: NO_FILES [${date_step} ${hour_get}]"
        echo "----- [${date_step} ${hour_get}] end (no files)"
        echo " ===> HOUR_STEP: $hour_get ===> END "
        continue
      fi

      # 2) For each file, run a short controlled download and print per-file status
      for fname in "${file_list[@]}"; do
        # Defensive trim
        fname="$(echo -n "${fname}" | tr -d '\r')"
        [ -z "${fname}" ] && continue

        echo "SRC: ${ftp_url}${ftp_folder_def}/${fname}"
        echo "DST: ${local_folder_def}${fname}"

        set +e
        timeout --preserve-status "${TIMEOUT_LFTP_SECS}" lftp -u "${ftp_usr},${ftp_pwd}" "${ftp_url}" <<LFTP_GET
${LFTP_COMMON_SETTINGS}
set ftp:proxy ${proxy};
open ${ftp_url}
cd ${ftp_folder_def}
lcd ${local_folder_def}
get -c "${fname}"
quit
LFTP_GET
        rc_file=$?
        set -e

        per_file_attempts=$((per_file_attempts+1))
        if [[ ${rc_file} -eq 0 ]]; then
          echo "STATUS: SUCCESS [${date_step} ${hour_get}] FILE: ${fname}"
        elif [[ ${rc_file} -eq 124 ]]; then
          echo "STATUS: TIMEOUT [${date_step} ${hour_get}] FILE: ${fname}"
        else
          echo "STATUS: FAIL [${date_step} ${hour_get}] FILE: ${fname} (rc=${rc_file})"
        fi
      done

      echo "----- [${date_step} ${hour_get}] end (per-file)"
    fi

    echo " ===> HOUR_STEP: $hour_get ===> END "
  done

  echo " ===> TIME_STEP: $date_step ===> END "
done

# If we appended commands for single-session mode, run them now
if [ "${PER_FILE_LOG}" != "true" ] && (( added_cmds > 0 )); then
  # Close the single LFTP session cleanly at the end
  LFTP_SCRIPT+=$'\n'"close;"
  LFTP_SCRIPT+=$'\n'"quit;"

  echo " [LFTP] Starting single-session transfer (timeout ${TIMEOUT_LFTP_SECS}s)..."
  set +e
  timeout --preserve-status "${TIMEOUT_LFTP_SECS}" bash -c "lftp <<'LFTP_EOF'
${LFTP_SCRIPT}
LFTP_EOF"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    echo " [LFTP] Session completed successfully."
  elif [[ $rc -eq 124 ]]; then
    echo " [LFTP] Session timed out after ${TIMEOUT_LFTP_SECS}s."
  else
    echo " [LFTP] Session exited with rc=$rc."
  fi
fi

# If nothing happened in either mode, say so and exit
if (( added_cmds == 0 )) && (( per_file_attempts == 0 )); then
  echo " [INFO] Nothing to do (no eligible hours/files). Exiting."
fi

echo " ==> $script_name (Version: $script_version Release_Date: $script_date)"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="

