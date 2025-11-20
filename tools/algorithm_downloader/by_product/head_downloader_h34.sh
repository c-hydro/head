#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

########################################
# CONFIG (adjust to your environment)
########################################

# Absolute path to the Python script
PY_SCRIPT="/root/projects/hsaf/algorithm_downloader/head_downloader_h34.py"

# Python interpreter (or your venv python)
PY_BIN="/usr/bin/python3"
# Example for venv:
# PY_BIN="/root/projects/hsaf/venv/bin/python"

# .netrc machine label (must match entry in ~/.netrc)
export NETRC_MACHINE_LABEL="ftphsaf.meteoam.it"

# FTP host
export FTP_URL="ftphsaf.meteoam.it"

# Mode (for logging only)
export SCRIPT_MODE="realtime"

# How many days back (0 = only today)
export DAYS="7"

# Local storage pattern (keep in sync with Python script)
export LOCAL_FOLDER_RAW="/share/HSAF_SNOW/nrt/h34/%YYYY/%MM/%DD/"

# Remote FTP folder
export FTP_FOLDER="/products/h34/h34_cur_mon_data"

# Optional staging directory (empty = disabled)
export STAGING_DIR=""

# Rate limiting (matches H60)
export CONN_LIMIT="1"
export LIMIT_RATE="0"          # bytes/s (0 = unlimited)
export LIMIT_TOTAL_RATE="0"    # bytes/s (0 = unlimited)

# LFTP monitoring directory
export LFTP_MONITOR_OUT_DIR="/share/MONITORING/ftp_connections/"

# Optional proxy
export PROXY=""

# Where to log this wrapper + python output
LOG_DIR="/share/LOGS/hsaf_h34"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/hsaf_h34_$(date +%Y%m%d).log"

########################################
# RUNTIME
########################################

# Everything inside { } is sent to both log file AND stdout via tee
{
  echo "============================================================"
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] START H34 PYTHON DOWNLOADER"
  echo "Script : $PY_SCRIPT"
  echo "Mode   : ${SCRIPT_MODE}"
  echo "Days   : ${DAYS}"
  echo "============================================================"

  # Optional: cd to project folder
  cd "$(dirname "$PY_SCRIPT")"

  # Run Python script (ALL its prints will appear here)
  "$PY_BIN" "$PY_SCRIPT"
  rc=$?

  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] END H34 PYTHON DOWNLOADER (rc=${rc})"
  echo
} 2>&1 | tee -a "$LOG_FILE"

