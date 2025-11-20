#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

########################################
# CONFIG (adjust to your environment)
########################################

# Absolute path to the Python script
PY_SCRIPT="/root/projects/hsaf/algorithm_downloader/head_downloader_h29.py"

# Python interpreter (or your venv python)
PY_BIN="/usr/bin/python3"
# Example for venv:
# PY_BIN="/root/projects/hsaf/venv/bin/python"

# .netrc machine label (must match entry in ~/.netrc)
export NETRC_MACHINE_LABEL="ftphsaf.meteoam.it"

# FTP host (optional override, normally same as machine label)
export FTP_URL="ftphsaf.meteoam.it"

# Mode: realtime or history
export SCRIPT_MODE="realtime"

# How many hours back (0 = only current hour)
export HOURS_BACK="4"

# Local storage pattern (keep in sync with your Python script logic)
export LOCAL_FOLDER_RAW="/share/HSAF_SM/ascat/nrt/h29/%YYYY/%MM/%DD/%HH/"

# Remote folder template
export FTP_FOLDER_RAW="/products/h29/h29_cur_mon_nc/"

# Safety lag on current hour (minutes)
export SAFETY_LAG_MIN="5"

# LFTP monitoring dir (same used in Python script)
export LFTP_MONITOR_OUT_DIR="/share/MONITORING/ftp_connections/"

# Optional: proxy (leave empty if unused)
export PROXY=""

# Where to log this wrapper + python output
LOG_DIR="/share/LOGS/hsaf_h29"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/hsaf_h29_$(date +%Y%m%d).log"

########################################
# RUNTIME
########################################

# Everything inside { } is sent to both log file AND stdout via tee
{
  echo "============================================================"
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] START H29 PYTHON DOWNLOADER"
  echo "Script : $PY_SCRIPT"
  echo "Mode   : ${SCRIPT_MODE}"
  echo "Hours  : ${HOURS_BACK}"
  echo "============================================================"

  # Optional: cd to project folder
  cd "$(dirname "$PY_SCRIPT")"

  # Run Python script (ALL its prints will appear here)
  "$PY_BIN" "$PY_SCRIPT"
  rc=$?

  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] END H29 PYTHON DOWNLOADER (rc=${rc})"
  echo
} 2>&1 | tee -a "$LOG_FILE"

