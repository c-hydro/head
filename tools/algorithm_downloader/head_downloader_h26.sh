#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# =======================================================================================
# Script information
script_name='HEAD DOWNLOADER - HSAF PRODUCT SOIL MOISTURE H26 - REALTIME'
script_version="1.0.0"
script_date='2025/11/11'
# =======================================================================================

# -------------------------------------
# Defaults (override via environment)
# -------------------------------------
DATA_FOLDER_RAW="${DATA_FOLDER_RAW:-/share/HSAF_SM/ecmwf/nrt/h26/%YYYY/%MM/%DD/}"
DAYS="${DAYS:-12}"                          # how many days back from START_DATE_UTC to include
START_DATE_UTC="${START_DATE_UTC:-today}"   # anchor day in UTC (e.g., "2025-11-11", "yesterday", "2025-11-01 00:00")

# If set, download to staging first, then move into DATA_FOLDER_RAW
STAGING_DIR="${STAGING_DIR:-}"              # e.g., /tmp/hsaf_staging

PROXY="${PROXY:-}"

FTP_URL="${FTP_URL:-ftphsaf.meteoam.it}"
FTP_USR="${FTP_USR:-${HSAF_FTP_USER:-}}"
FTP_PWD="${FTP_PWD:-${HSAF_FTP_PASS:-}}"
FTP_FOLDER="${FTP_FOLDER:-/products/h26/h26_cur_mon_nc}"

# File pattern template (remote file name)
FILE_PATTERN_TEMPLATE="${FILE_PATTERN_TEMPLATE:-h26_%YYYY%MM%DD00_R01.nc}"

# Connection limiting
CONN_LIMIT="${CONN_LIMIT:-1}"
PGET_N="${PGET_N:-1}"                        # segments per file (resumable)
LIMIT_RATE="${LIMIT_RATE:-0}"                # per-connection (bytes/s), 0 = unlimited
LIMIT_TOTAL_RATE="${LIMIT_TOTAL_RATE:-0}"    # total (bytes/s), 0 = unlimited

# Behavior
DRY_RUN="${DRY_RUN:-false}"                  # don't actually download/move
RESET_EXISTING="${RESET_EXISTING:-false}"    # remove target file and re-download if present
VERBOSE="${VERBOSE:-true}"

# Locking
LOCKFILE="${LOCKFILE:-/tmp/hsaf_h26_downloader.lock}"

# Auto-detect .netrc
USE_NETRC=false
if [[ -f "${HOME}/.netrc" && -z "${FTP_USR:-}" && -z "${FTP_PWD:-}" ]]; then
  USE_NETRC=true
fi

# Default file permissions
umask "${UMASK_OVERRIDE:-002}"

# =======================================================================================
# Helpers
# =======================================================================================
log() {
  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [[ "${VERBOSE}" == "true" ]]; then printf "[%s] %s\n" "${ts}" "$*"; fi
}
die() { log "ERROR: $*"; exit 1; }

require_bin() {
  command -v "$1" >/dev/null 2>&1 || die "Required executable not found in PATH: $1"
}

_date() {
  if date --version >/dev/null 2>&1; then date "$@"
  elif command -v gdate >/dev/null 2>&1; then gdate "$@"
  else die "GNU date required (Linux 'date' or 'gdate' on macOS)."
  fi
}

to_utc_ymd() { _date -u -d "$1" +%Y-%m-%d; }

mk_target_dir() {
  local y="$1" m="$2" d="$3"
  local path="${DATA_FOLDER_RAW//'%'YYYY/$y}"
  path="${path//'%'MM/$m}"
  path="${path//'%'DD/$d}"
  path="${path//'%'HH/00}"
  printf "%s" "$path"
}

mk_file_pattern() {
  local y="$1" m="$2" d="$3"
  local pattern="${FILE_PATTERN_TEMPLATE//'%'YYYY/$y}"
  pattern="${pattern//'%'MM/$m}"
  pattern="${pattern//'%'DD/$d}"
  printf "%s" "$pattern"
}

# Run an lftp session with broadly compatible settings. Pass a single here-doc body as $1.
lftp_run() {
  local cmd="$1"
  local auth="open ${FTP_URL}"
  if ! $USE_NETRC; then
    [[ -n "${FTP_USR:-}" && -n "${FTP_PWD:-}" ]] || die "FTP credentials not provided and ~/.netrc not found."
    auth="open -u ${FTP_USR},${FTP_PWD} ${FTP_URL}"
  fi

  lftp <<EOF
set ftp:proxy ${PROXY}
set net:timeout 30
set net:max-retries 5
set net:persist-retries 1
set cmd:fail-exit yes
set xfer:clobber on
set ftp:ssl-allow true
set ftp:passive-mode true
set net:connection-limit ${CONN_LIMIT}
set pget:default-n ${PGET_N}
set mirror:use-pget-n ${PGET_N}
set net:limit-rate ${LIMIT_RATE}
set net:limit-total-rate ${LIMIT_TOTAL_RATE}
${auth}
${cmd}
bye
EOF
}

# Safe move (across filesystems). Uses mv, falls back to cp+sync+rm.
safe_move() {
  local src="$1" dst="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: would move '${src}' -> '${dst}'"
    return 0
  fi
  if mv -f -- "$src" "$dst" 2>/dev/null; then
    return 0
  fi
  cp -f -- "$src" "$dst"
  sync
  rm -f -- "$src"
}

usage() {
cat <<USAGE
${script_name} ${script_version}  (${script_date})

Downloads HSAF H26 daily NetCDF files from ${FTP_URL}${FTP_FOLDER} into a YYYY/MM/DD tree.

Environment variables:
  DATA_FOLDER_RAW       Target dir template [${DATA_FOLDER_RAW}]
  STAGING_DIR           Optional staging dir (uses target if empty)
  DAYS                  Days back from START_DATE_UTC (inclusive) [${DAYS}]
  START_DATE_UTC        Anchor date in UTC (e.g. 'today', '2025-11-01') [${START_DATE_UTC}]
  FTP_URL               Host [${FTP_URL}]
  FTP_FOLDER            Remote folder [${FTP_FOLDER}]
  FILE_PATTERN_TEMPLATE Remote filename template [${FILE_PATTERN_TEMPLATE}]
  HSAF_FTP_USER/FTP_USR, HSAF_FTP_PASS/FTP_PWD
  PROXY                 e.g. http://host:port  [${PROXY:-<none>}]
  CONN_LIMIT            Parallel connections to server [${CONN_LIMIT}]
  PGET_N                Segments per file (resumable) [${PGET_N}]
  LIMIT_RATE            Per-connection rate (bytes/s) [${LIMIT_RATE}]
  LIMIT_TOTAL_RATE      Total rate (bytes/s) [${LIMIT_TOTAL_RATE}]
  DRY_RUN               true/false [${DRY_RUN}]
  RESET_EXISTING        true/false [${RESET_EXISTING}]
  VERBOSE               true/false [${VERBOSE}]
  LOCKFILE              [${LOCKFILE}]

Examples:
  START_DATE_UTC=today DAYS=12 ./hsaf_h26_downloader.sh
  HSAF_FTP_USER=xxx HSAF_FTP_PASS=yyy START_DATE_UTC=2025-11-10 DAYS=3 ./hsaf_h26_downloader.sh
  DRY_RUN=true DAYS=1 ./hsaf_h26_downloader.sh
  START_DATE_UTC=2025-11-09 DAYS=0 RESET_EXISTING=true ./hsaf_h26_downloader.sh
USAGE
}

# Trap & lock
trap 'die "Unexpected failure (line $LINENO)."' ERR

# =======================================================================================
# Pre-flight
# =======================================================================================
for b in lftp awk sed sort mktemp; do require_bin "$b"; done
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi

# Lock to avoid concurrent runs
exec 9> "${LOCKFILE}"
if ! flock -n 9; then
  die "Another instance is running (lock: ${LOCKFILE})"
fi

# =======================================================================================
# Startup summary
# =======================================================================================
echo " ==================================================================================="
echo " 🌱 ${script_name} - Runtime Summary"
echo " -----------------------------------------------------------------------------------"
printf " Version:             %s\n" "${script_version}"
printf " Release Date:        %s\n" "${script_date}"
printf " Output Template:     %s\n" "${DATA_FOLDER_RAW}"
printf " Days Back:           %s\n" "${DAYS}"
printf " Anchor Date (UTC):   %s\n" "${START_DATE_UTC}"
printf " FTP Host:            %s\n" "${FTP_URL}"
printf " FTP Folder:          %s\n" "${FTP_FOLDER}"
printf " File Pattern:        %s\n" "${FILE_PATTERN_TEMPLATE}"
printf " Use .netrc:          %s\n" "${USE_NETRC}"
printf " Proxy:               %s\n" "${PROXY:-<none>}"
printf " Conn Limit:          %s\n" "${CONN_LIMIT}"
printf " Segments per File:   %s\n" "${PGET_N}"
printf " Limit Rate (per):    %s\n" "${LIMIT_RATE}"
printf " Limit Rate (total):  %s\n" "${LIMIT_TOTAL_RATE}"
printf " Staging Dir:         %s\n" "${STAGING_DIR:-<none>}"
printf " Dry Run:             %s\n" "${DRY_RUN}"
printf " Reset Existing:      %s\n" "${RESET_EXISTING}"
echo " ==================================================================================="

# =======================================================================================
# Main
# =======================================================================================
log "==> START"
anchor_ymd="$(to_utc_ymd "${START_DATE_UTC}")"
log "Anchor UTC date: ${anchor_ymd} ; Days back: ${DAYS}"

for ((i=0; i<=DAYS; i++)); do
  ymd="$(_date -u -d "${anchor_ymd} - ${i} days" +%Y-%m-%d)"
  y="$(_date -u -d "${ymd}" +%Y)"
  m="$(_date -u -d "${ymd}" +%m)"
  d="$(_date -u -d "${ymd}" +%d)"
  pattern="$(mk_file_pattern "$y" "$m" "$d")"

  # Direct target directory
  target_dir="$(mk_target_dir "$y" "$m" "$d")"
  target_file="${target_dir}/${pattern}"

  # Staging directory (optional)
  if [[ -n "${STAGING_DIR}" ]]; then
    stage_dir="${STAGING_DIR%/}/${y}/${m}/${d}"
  else
    stage_dir="${target_dir}"
  fi
  stage_file="${stage_dir}/${pattern}"

  if [[ "${RESET_EXISTING}" == "true" && -f "${target_file}" ]]; then
    log "RESET: removing existing ${target_file}"
    [[ "${DRY_RUN}" == "true" ]] || rm -f -- "${target_file}"
  fi

  mkdir -p -- "${stage_dir}" "${target_dir}"

  log "====> TIME_STEP: ${y}-${m}-${d} ===> START (target: ${target_dir})"
  log "Pattern: ${pattern}"

  # --- skip if already present in final destination ---
  if [[ -f "${target_file}" && -s "${target_file}" ]]; then
    echo "----- SKIPPED ${y}-${m}-${d} -----"
    echo "File already exists locally:"
    echo "  ${target_file}"
    log "Skipping FTP connection for ${pattern}"
    continue
  fi

  # --- check remote existence first (older lftp exits hard on 550) ---
  if ! lftp_run "cd ${FTP_FOLDER}; cls -1 ${pattern}" | grep -qx "${pattern}"; then
    echo "No remote file found for ${y}-${m}-${d} (pattern: ${pattern}). Skipping."
    log "Remote missing or not yet published."
    continue
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "DRY-RUN: would download ${FTP_FOLDER}/${pattern} -> ${stage_file}"
    continue
  fi

  session_log="$(mktemp)"

  # --- download exact file with pget, forcing local CWD ---
  if ! lftp_run "
    lcd ${stage_dir}
    cd ${FTP_FOLDER}
    pget -n ${PGET_N} -c ${pattern}
  " | tee "${session_log}"; then
    echo "lftp pget failed for ${pattern}"
    tail -n 50 "${session_log}" || true
    rm -f "${session_log}"
    die "lftp pget failed for ${pattern}"
  fi

  # --- verify staging file exists and is non-empty ---
  if [[ ! -s "${stage_file}" ]]; then
    echo "No file present locally after transfer for ${y}-${m}-${d} (pattern: ${pattern})."
    echo "Last lftp session log snippet:"
    tail -n 50 "${session_log}" || true
    rm -f "${session_log}"
    die "Transfer reported but file not found: ${stage_file}"
  fi

  # --- move from staging to final (if needed) ---
  if [[ "${stage_dir}" != "${target_dir}" ]]; then
    safe_move "${stage_file}" "${target_file}"
  fi

  # --- final verification ---
  if [[ -s "${target_file}" ]]; then
    echo "----- Downloaded files for ${y}-${m}-${d} -----"
    echo "Source: ${FTP_URL}${FTP_FOLDER}"
    echo "Destination: ${target_dir}"
    echo "Pattern: ${pattern}"
    echo "-----------------------------------------------"
    echo "  • ${FTP_FOLDER}/${pattern}"
  else
    echo "File missing after move for ${y}-${m}-${d}: ${target_file}"
    tail -n 50 "${session_log}" || true
    rm -f "${session_log}"
    die "File verification failed: ${target_file}"
  fi

  rm -f "${session_log}"
  log "====> TIME_STEP: ${y}-${m}-${d} ===> END"

done

log "==> ${script_name} (Version: ${script_version} Release_Date: ${script_date})"
log "==> ... END"
log "==> Bye, Bye"
# =======================================================================================

