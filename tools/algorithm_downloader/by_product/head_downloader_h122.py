#!/usr/bin/env python3
import argparse
import datetime as dt
import os
import subprocess
import sys
from pathlib import Path
from netrc import netrc
from collections import defaultdict

# ----------------------------------------------------------------------------------------
# Script information
SCRIPT_NAME = "HEAD DOWNLOADER - HSAF SOIL MOISTURE H122 (ASCAT METOP A/B/C)"
SCRIPT_VERSION = "1.3.0"
SCRIPT_DATE = "2025/11/11"

# === User settings (H122) ===============================================================

# .netrc machine label to use (e.g., "ftphsaf.meteoam.it" or "..._sg")
NETRC_MACHINE_LABEL = os.environ.get("NETRC_MACHINE_LABEL", "ftphsaf.meteoam.it")

# Actual FTP host
FTP_URL = os.environ.get("FTP_URL", "ftphsaf.meteoam.it")

# Optional proxy (or empty, like original script)
PROXY = os.environ.get("PROXY", "")

# Mode: 'realtime' or 'history'
SCRIPT_MODE = os.environ.get("SCRIPT_MODE", "realtime")  # "realtime" or "history"

# Hours back inclusive (0 = current hour only)
HOURS_BACK = int(os.environ.get("HOURS_BACK", "4"))

# Local path pattern (H122)
LOCAL_FOLDER_RAW = os.environ.get(
    "LOCAL_FOLDER_RAW",
    "/share/HSAF_SM/ascat/nrt/h122/%YYYY/%MM/%DD/%HH/",
)

# Remote folder template (H122)
if SCRIPT_MODE == "realtime":
    FTP_FOLDER_RAW = os.environ.get(
        "FTP_FOLDER_RAW", "/products/h122/h122_cur_mon_nc/"
    )
else:
    FTP_FOLDER_RAW = os.environ.get(
        "FTP_FOLDER_RAW", "/products/h122_test/h122_cur_mon_nc/"
    )

# Skip current hour if too “fresh”
SAFETY_LAG_MIN = int(os.environ.get("SAFETY_LAG_MIN", "5"))

# LFTP common settings
LFTP_COMMON_SETTINGS = [
    "set cmd:fail-exit yes;",
    "set net:timeout 30;",
    "set net:max-retries 3;",
    "set net:reconnect-interval-base 5;",
    "set net:reconnect-interval-max 20;",
    "set ftp:passive-mode yes;",
    "set xfer:clobber on;",
    # "set cmd:trace yes;",
]

# LFTP timeout (seconds) for the big download session
TIMEOUT_LFTP_SECS = int(os.environ.get("TIMEOUT_LFTP_SECS", "600"))

# === LFTP MONITORING ================================================================

LFTP_MONITOR_OUT_DIR = Path(
    os.environ.get("LFTP_MONITOR_OUT_DIR", "/share/MONITORING/ftp_connections/")
)
LFTP_MONITOR_TODAY = dt.datetime.utcnow().strftime("%Y%m%d")
LFTP_MONITOR_LOG = Path(
    os.environ.get(
        "LFTP_MONITOR_LOG",
        str(LFTP_MONITOR_OUT_DIR / f"lftp_requests_{LFTP_MONITOR_TODAY}.log"),
    )
)

SCRIPT_ID = str(Path(__file__).resolve())


def log_lftp_call(body: str) -> None:
    """Append a monitoring line: TIMESTAMP|SCRIPT|COMMAND."""
    LFTP_MONITOR_OUT_DIR.mkdir(parents=True, exist_ok=True)
    compact = " ".join(body.split())
    ts = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    with LFTP_MONITOR_LOG.open("a", encoding="utf-8") as f:
        f.write(f"{ts}|{SCRIPT_ID}|{compact}\n")


# =======================================================================================
# Helpers
# =======================================================================================

def load_netrc_creds(machine_label: str) -> tuple[str, str]:
    """Return (login, password) for the given machine label from ~/.netrc."""
    netrc_path = os.path.expanduser("~/.netrc")
    if not os.path.exists(netrc_path):
        print(f" [ERROR] {netrc_path} not found; create it and chmod 600.", file=sys.stderr)
        sys.exit(1)

    try:
        n = netrc(netrc_path)
        auth = n.authenticators(machine_label)
    except Exception as exc:
        print(f" [ERROR] Failed reading {netrc_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    if auth is None or auth[0] is None or auth[2] is None:
        print(f' [ERROR] No credentials found in ~/.netrc for machine "{machine_label}".',
              file=sys.stderr)
        print(" [HINT] Available machine labels:", file=sys.stderr)
        for host, (login, _account, _pwd) in n.hosts.items():
            print(f"   - {host}", file=sys.stderr)
        sys.exit(1)

    login, _, password = auth
    return login, password


def build_paths_for_hour(ts: dt.datetime) -> tuple[str, str, str, str]:
    """
    Given a datetime, build:
      - date_step_str: YYYYMMDD
      - hour_get: HH
      - ftp_folder_def
      - local_folder_def
    """
    date_step_str = ts.strftime("%Y%m%d")
    year_get = ts.strftime("%Y")
    month_get = ts.strftime("%m")
    day_get = ts.strftime("%d")
    hour_get = ts.strftime("%H")

    ftp_folder_def = (
        FTP_FOLDER_RAW.replace("%YYYY", year_get)
        .replace("%MM", month_get)
        .replace("%DD", day_get)
        .replace("%HH", hour_get)
    )
    local_folder_def = (
        LOCAL_FOLDER_RAW.replace("%YYYY", year_get)
        .replace("%MM", month_get)
        .replace("%DD", day_get)
        .replace("%HH", hour_get)
    )

    return date_step_str, hour_get, ftp_folder_def, local_folder_def


def list_remote_files(ftp_user: str, ftp_pwd: str, ftp_folder: str, pattern: str) -> list[str]:
    """
    Use a short lftp call to list remote files matching 'pattern' in 'ftp_folder'.
    Returns a list of filenames (no paths).
    """
    cmd = [
        "lftp",
        "-u",
        f"{ftp_user},{ftp_pwd}",
        FTP_URL,
        "-e",
        f"set ftp:proxy {PROXY}; "
        + "; ".join(LFTP_COMMON_SETTINGS) + "; "
        + f"cd {ftp_folder}; "
        + f"cls -1 {pattern}; "
        + "bye;"
    ]
    try:
        result = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=TIMEOUT_LFTP_SECS,
        )
    except subprocess.TimeoutExpired:
        print(f" [WARN] Timeout listing {ftp_folder} with pattern {pattern}", file=sys.stderr)
        return []

    if result.returncode != 0:
        # Could be simply "no such file" or folder not existing
        return []

    files = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        # Basic filter: skip messages that are obviously not filenames
        if line.lower().startswith("ls:") or line.lower().startswith("mirror:"):
            continue
        files.append(line)
    return files


def build_lftp_download_script(
    ftp_user: str,
    ftp_pwd: str,
    jobs: list[tuple[str, str, str]],
) -> str:
    """
    Build a single lftp script that:
    - sets common options
    - opens one session
    - for each (ftp_folder, local_folder, filename) in jobs:
        cd / lcd as needed, then get -c file
    - closes session
    """
    lines: list[str] = []

    # Proxy + common settings
    if PROXY:
        lines.append(f"set ftp:proxy {PROXY};")
    else:
        lines.append("set ftp:proxy ;")
    lines.extend(LFTP_COMMON_SETTINGS)

    # Open one session
    lines.append(f"open -u {ftp_user},{ftp_pwd} {FTP_URL};")

    # Group jobs by (ftp_folder, local_folder)
    grouped: dict[tuple[str, str], list[str]] = defaultdict(list)
    for ftp_folder, local_folder, filename in jobs:
        grouped[(ftp_folder, local_folder)].append(filename)

    current_remote = None
    current_local = None

    for (ftp_folder, local_folder), files in grouped.items():
        lines.append(f"echo '=== SESSION BLOCK: SRC={ftp_folder} DST={local_folder} ===';")
        if ftp_folder != current_remote:
            lines.append(f"cd {ftp_folder};")
            current_remote = ftp_folder
        if local_folder != current_local:
            lines.append(f"lcd {local_folder};")
            current_local = local_folder

        for fname in files:
            lines.append(f"echo 'DOWNLOAD {fname}';")
            lines.append(f"get -c {fname};")

    lines.append("close;")
    lines.append("quit;")

    script_str = "\n".join(lines) + "\n"
    return script_str


def run_lftp(script_text: str) -> int:
    """Run lftp with the provided script via stdin, with timeout + monitoring."""
    # Log the full script in monitoring file
    log_lftp_call(script_text)

    try:
        print(f" [LFTP] Starting single-session transfer (timeout {TIMEOUT_LFTP_SECS}s)...")
        result = subprocess.run(
            ["lftp"],
            input=script_text,
            text=True,
            capture_output=False,
            timeout=TIMEOUT_LFTP_SECS,
        )
        return result.returncode
    except subprocess.TimeoutExpired:
        print(f" [LFTP] Session timed out after {TIMEOUT_LFTP_SECS}s.", file=sys.stderr)
        return 124


# =======================================================================================
# main
# =======================================================================================

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=f"{SCRIPT_NAME} (Python, single-session lftp, hours-based, per-file logic)"
    )
    parser.add_argument(
        "-f", "--force", action="store_true",
        help="(kept for compatibility, no effect in Python version yet)",
    )

    _args = parser.parse_args(argv)

    print(" ===================================================================================")
    print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
    print(" ==> START ...")
    print(f" ==> Mode: {SCRIPT_MODE} ; Hours back: {HOURS_BACK}")
    print(f" ==> FTP Host: {FTP_URL}")
    print(f" ==> Local template: {LOCAL_FOLDER_RAW}")
    print(f" ==> FTP template:   {FTP_FOLDER_RAW}")
    print(" ===================================================================================")

    ftp_usr, ftp_pwd = load_netrc_creds(NETRC_MACHINE_LABEL)
    print(f" ===> INFO MACHINE -- URL: {FTP_URL} -- NETRC: {NETRC_MACHINE_LABEL} -- USER: {ftp_usr}")

    now_local = dt.datetime.now()
    now_min = now_local.minute

    download_jobs: list[tuple[str, str, str]] = []

    # Walk back hour by hour, PLAN phase (list + decide)
    for offset in range(HOURS_BACK + 1):
        ts = now_local - dt.timedelta(hours=offset)
        date_step_str, hour_get, ftp_folder_def, local_folder_def = build_paths_for_hour(ts)

        print(f"\n ===> TIME_STEP: {date_step_str} HOUR: {hour_get} ===> START ")

        # Safety lag: only affect current hour in realtime mode
        if SCRIPT_MODE == "realtime" and offset == 0:
            if now_min < SAFETY_LAG_MIN:
                print(
                    f"  [INFO] Current hour within safety lag "
                    f"({SAFETY_LAG_MIN}m). Skipping this hour."
                )
                print(f" ===> TIME_STEP: {date_step_str} HOUR: {hour_get} ===> END ")
                continue

        # Local folder
        local_dir = Path(local_folder_def)
        local_dir.mkdir(parents=True, exist_ok=True)

        # Pattern for this hour
        file_pattern = f"*H122_C_LIIB_{date_step_str}{hour_get}*"

        print(f"  [INFO] Target FTP folder: {ftp_folder_def}")
        print(f"  [INFO] Target LOCAL folder: {local_folder_def}")
        print(f"  [INFO] LIST PATTERN: {file_pattern}")

        # Step 1: list remote files for this pattern
        remote_files = list_remote_files(ftp_usr, ftp_pwd, ftp_folder_def, file_pattern)

        if not remote_files:
            print("  [INFO] No remote files found for this pattern.")
            print(f" ===> TIME_STEP: {date_step_str} HOUR: {hour_get} ===> END ")
            continue

        # Step 2: for each remote file, check local existence and decide
        for fname in remote_files:
            local_path = local_dir / fname
            if local_path.is_file() and local_path.stat().st_size > 0:
                print(f"    FILE: {fname} => SKIP (local exists)")
            else:
                print(f"    FILE: {fname} => DOWNLOAD (missing locally)")
                download_jobs.append((ftp_folder_def, local_folder_def, fname))

        print(f" ===> TIME_STEP: {date_step_str} HOUR: {hour_get} ===> END ")

    # If nothing to download, we can exit
    if not download_jobs:
        print(" [INFO] Nothing to download (all files already present or no remote files).")
        print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
        print(" ==> ... END")
        print(" ==> Bye, Bye")
        print(" ===================================================================================")
        return 0

    # Build single-session lftp script for the DOWNLOAD phase
    lftp_script = build_lftp_download_script(ftp_usr, ftp_pwd, download_jobs)

    # Run lftp once for all downloads
    rc = run_lftp(lftp_script)

    if rc == 0:
        print(" [LFTP] Session completed successfully.")
    elif rc == 124:
        print(" [LFTP] Session TIMEOUT.")
    else:
        print(f" [LFTP] Session exited with rc={rc}.")

    print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
    print(" ==> ... END")
    print(" ==> Bye, Bye")
    print(" ===================================================================================")

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

