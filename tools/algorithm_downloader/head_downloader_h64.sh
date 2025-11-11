#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# =======================================================================================
# Script information
script_name='HEAD DOWNLOADER - HSAF PRODUCT PRECIPITATION H64 - REALTIME'
script_version="2.4.1"
script_date='2025/11/11'
# =======================================================================================

# -------------------------------------
# Defaults (override via environment)
# -------------------------------------
DATA_FOLDER_RAW="${DATA_FOLDER_RAW:-/share/HSAF_PRECIPITATION/nrt/h64/%YYYY/%MM/%DD/}"
DAYS="${DAYS:-10}"
START_DATE_UTC="${START_DATE_UTC:-today}"

# If set, download to staging first, then move into DATA_FOLDER_RAW
STAGING_DIR="${STAGING_DIR:-}"   # e.g., /tmp/hsaf_staging

PROXY="${PROXY:-}"

FTP_URL="${FTP_URL:-ftphsaf.meteoam.it}"
FTP_USR="${FTP_USR:-${HSAF_FTP_USER:-}}"
FTP_PWD="${FTP_PWD:-${HSAF_FTP_PASS:-}}"
FTP_FOLDER="${FTP_FOLDER:-/products/h64/h64_cur_mon_data}"

# File pattern template [h64_%YYYY%MM%DD_0000_24_hea.nc.gz]
FILE_PATTERN_TEMPLATE="${FILE_PATTERN_TEMPLATE:-h64_%YYYY%MM%DD_0000_24_hea.nc.gz}"

# Connection limiting
CONN_LIMIT="${CONN_LIMIT:-1}"
PARALLEL="${PARALLEL:-1}"
PGET_N="${PGET_N:-1}"
LIMIT_RATE="${LIMIT_RATE:-0}"             # per-connection (bytes/s), 0 = unlimited
LIMIT_TOTAL_RATE="${LIMIT_TOTAL_RATE:-0}" # total (bytes/s), 0 = unlimited

# Auto-detect .netrc
USE_NETRC=false
if [[ -f "${HOME}/.netrc" && -z "${FTP_USR:-}" && -z "${FTP_PWD:-}" ]]; then
  USE_NETRC=true
fi

# Default file permissions (adjust if you like)
umask "${UMASK_OVERRIDE:-002}"

# =======================================================================================
# Helpers
# =======================================================================================
log() { printf "[%s] %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
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
  local path="${DATA_FOLDER_RAW//'%YYYY'/$y}"
  path="${path//'%MM'/$m}"
  path="${path//'%DD'/$d}"
  path="${path//'%HH'/00}"
  printf "%s" "$path"
}

mk_file_pattern() {
  local y="$1" m="$2" d="$3"
  local pattern="${FILE_PATTERN_TEMPLATE//'%YYYY'/$y}"
  pattern="${pattern//'%MM'/$m}"
  pattern="${pattern//'%DD'/$d}"
  printf "%s" "$pattern"
}

# Run an lftp session with broadly compatible settings. Pass a single here-doc body as $1.
lftp_run() {
  local cmd="$1"
  if $USE_NETRC; then
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
open ${FTP_URL}
${cmd}
bye
EOF
  else
    [[ -n "${FTP_USR:-}" && -n "${FTP_PWD:-}" ]] || die "FTP credentials not provided and ~/.netrc not found."
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
open -u ${FTP_USR},${FTP_PWD} ${FTP_URL}
${cmd}
bye
EOF
  fi
}

# Safe move (across filesystems). Uses mv, falls back to cp+sync+rm.
safe_move() {
  local src="$1" dst="$2"
  if mv -f -- "$src" "$dst" 2>/dev/null; then
    return 0
  fi
  cp -f -- "$src" "$dst"
  sync
  rm -f -- "$src"
}

trap 'die "Unexpected failure (line $LINENO)."' ERR

# =======================================================================================
# Pre-flight
# =======================================================================================
require_bin lftp
require_bin awk
require_bin sed
require_bin sort
require_bin mktemp

# =======================================================================================
# Startup summary
# =======================================================================================
echo " ==================================================================================="
echo " 🧊 ${script_name} - Runtime Summary"
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
printf " Connection Limit:    %s\n" "${CONN_LIMIT}"
printf " Parallel Downloads:  %s\n" "${PARALLEL}"
printf " Segments per File:   %s\n" "${PGET_N}"
printf " Limit Rate (per):    %s\n" "${LIMIT_RATE}"
printf " Limit Rate (total):  %s\n" "${LIMIT_TOTAL_RATE}"
printf " Staging Dir:         %s\n" "${STAGING_DIR:-<none>}"
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

  mkdir -p -- "$stage_dir" "$target_dir"

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

