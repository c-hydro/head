#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------------------------
# Script information
script_name='HEAD DOWNLOADER - HSAF PRODUCT PRECIPITATION H61/H61B'
script_version="2.9.7"
script_date='2025/11/11'

# ========================================================================================
# Parse arguments (currently: -f/--force, -p/--plan)
force_run=false
plan_mode=false
for arg in "$@"; do
  case "$arg" in
    -f|--force) force_run=true ;;
    -p|--plan)  plan_mode=true ;;
    *) ;;
  esac
done

# === Concurrency settings ===============================================================
MAX_INSTANCES=2
SEMAPHORE_TAG="hsaf_h61_downloader"
LOCK_DIR="/share/LOCKS/${SEMAPHORE_TAG}.locks"
mkdir -p "$LOCK_DIR"

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
    SLOT_ACQUIRED="$i"; LOCK_FD="$fd"; break
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

run_lftp_batch() {
  local script_body="$1"
  timeout --preserve-status "${TIMEOUT_LFTP_SECS}" bash -c "lftp <<'LFTP_EOF'
${script_body}
LFTP_EOF"
}

# Helper: does hour belong to 00/06/12/18?
is_synoptic_hour() {  # usage: is_synoptic_hour "HH"
  case "$1" in
    00|06|12|18) return 0 ;;
    *) return 1 ;;
  esac
}

# === Credential loader from ~/.netrc by machine label ===================================
load_netrc_creds() {
  local label="$1"
  local netrc_file="${HOME}/.netrc"
  if [[ ! -f "$netrc_file" ]]; then
    echo " [ERROR] ${netrc_file} not found; create it and chmod 600." >&2
    exit 1
  fi
  local out
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
netrc_machine_label="ftphsaf.meteoam.it"
ftp_url="ftphsaf.meteoam.it"
proxy=""

script_mode='realtime'   # 'realtime' or 'history'
days=0                   # 0=today only
local_folder_raw="/share/HSAF_PRECIPITATION/nrt/h61/%YYYY/%MM/%DD/"

if [ "$script_mode" == 'realtime' ]; then
  ftp_folder_raw="/products/h61/h61_cur_mon_data/"
else
  ftp_folder_raw="/hsaf_archive/h61/%YYYY/%MM/%DD/"
fi

# ----------------------------------------------------------------------------------------
time_now=$(date '+%Y-%m-%d')
now_day=$(date +%Y%m%d)
now_hour=$(date +%H)
now_min=$(date +%M)

echo " ==================================================================================="
echo " ==> $script_name (Version: $script_version Release_Date: $script_date)"
if [[ -n "${SLOT_ACQUIRED}" ]]; then
  echo " ==> Concurrency slot acquired: ${SLOT_ACQUIRED}/${MAX_INSTANCES}"
else
  echo " ==> Concurrency slot: forced (no slot acquired)"
fi
echo " ==> START ..."

# Load credentials
ftp_usr=""; ftp_pwd=""; load_netrc_creds "$netrc_machine_label"
echo " ===> INFO MACHINE -- URL: ${ftp_url} -- NETRC: ${netrc_machine_label} -- USER: ${ftp_usr}"

# ----------------------------------------------------------------------------------------
# Build the lftp command script (single session)
lftp_script=""
append_lftp() { lftp_script+="$1"$'\n'; }

append_lftp "set ftp:proxy ${proxy}"
while IFS= read -r line; do append_lftp "$line"; done <<<"$LFTP_COMMON_SETTINGS"
append_lftp "open -u ${ftp_usr},${ftp_pwd} ${ftp_url}"
append_lftp "echo ===== Connected to ${ftp_url} as ${ftp_usr} ====="

append_lftp "set cmd:fail-exit no"

if $plan_mode; then
  echo " [PLAN] Plan mode enabled — listing remote availability; no downloads."
fi

for day in $(seq 0 "$days"); do
  date_step=$(date -d "${time_now} -${day} days" +%Y%m%d)
  echo " ===> TIME_STEP: $date_step ===> START "

  year_get=$(date -u -d "$date_step" +"%Y")
  month_get=$(date -u -d "$date_step" +"%m")
  day_get=$(date -u -d "$date_step" +"%d")

  if [ "$script_mode" == 'realtime' ]; then
    if [[ "$date_step" == "$now_day" ]]; then
      count_start=$((10#$now_hour))
      count_end=0
    else
      count_start=23; count_end=0
    fi
  else
    count_start=23; count_end=0
  fi

  for hour in $(seq ${count_start} -1 ${count_end}); do
    hour_get=$(printf "%02d" ${hour})
    echo " ===> HOUR_STEP: $hour_get ===> START "

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

    echo "  [INFO] Target FTP folder: ${ftp_folder_def}"
    echo "  [INFO] Target LOCAL folder: ${local_folder_def}"

    append_lftp "cd ${ftp_folder_def} && echo '  [DIR OK] ${ftp_folder_def}' || echo '  [WARN] Cannot enter remote dir: ${ftp_folder_def}'"

    # ----- H61 hourly products -----------------------------------------------------------
    # Build expected filenames for H61 at this hour
    expected_files=( "h61_${date_step}_${hour_get}00_01_fdk.nc.gz" )
    if is_synoptic_hour "$hour_get"; then
      expected_files+=( "h61_${date_step}_${hour_get}00_24_fdk.nc.gz" )
    fi

    for ftp_file in "${expected_files[@]}"; do
      local_target="${local_folder_def}/${ftp_file}"

      append_lftp "echo '--- FILE ---'"
      append_lftp "echo 'file_name: ${ftp_file}'"
      append_lftp "echo 'src_folder: ${ftp_folder_def}'"
      append_lftp "echo 'dst_folder: ${local_folder_def}'"
      append_lftp "cd ${ftp_folder_def} && echo 'dir_ok: YES' || echo 'dir_ok: NO'"

      if [[ -e "$local_target" ]]; then
        append_lftp "echo 'status: SKIP (exists locally)'"
        append_lftp "cls -1 ${ftp_file} && echo 'remote: AVAILABLE' || echo 'remote: NOT_FOUND'"
        append_lftp "echo 'action: SKIP (already downloaded)'"
        continue
      fi

      append_lftp "echo 'status: NEEDED'"
      append_lftp "cls -1 ${ftp_file} && echo 'remote: AVAILABLE' || echo 'remote: NOT_FOUND'"

      if $plan_mode; then
        append_lftp "cls -1 ${ftp_file} && echo 'action: PLAN WOULD DOWNLOAD' || echo 'action: PLAN WAITING (remote not yet published)'"
      else
        append_lftp "cls -1 ${ftp_file} && echo 'action: DOWNLOAD' && get -c -O ${local_folder_def} ${ftp_file} || echo 'action: SKIP (remote missing)'"
      fi
    done
    # -------------------------------------------------------------------------------------

    echo " ===> HOUR_STEP: $hour_get ===> END "
  done

  echo " ===> TIME_STEP: $date_step ===> END "
done

append_lftp "close"
append_lftp "quit"

# ----------------------------------------------------------------------------------------
echo " [LFTP] Starting single-session ${plan_mode:+(plan-mode)} ..."
set +e
run_lftp_batch "${lftp_script}"
lftp_rc=$?
set -e

if $plan_mode; then
  if [[ $lftp_rc -ne 0 ]]; then
    echo " [LFTP] Plan session completed with rc=${lftp_rc} (listings only)."
  else
    echo " [LFTP] Plan session completed successfully."
  fi
else
  if [[ $lftp_rc -eq 0 ]]; then
    echo " [LFTP] Session completed successfully."
  elif [[ $lftp_rc -eq 124 ]]; then
    echo " [LFTP] Session TIMEOUT after ${TIMEOUT_LFTP_SECS}s."
  else
    echo " [LFTP] Session exited with rc=${lftp_rc}."
  fi
fi

echo " ==> $script_name (Version: $script_version Release_Date: $script_date)"
echo " ==> ... END"
echo " ==> Bye, Bye"
echo " ==================================================================================="

