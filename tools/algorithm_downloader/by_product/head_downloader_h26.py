#!/usr/bin/env python3
import argparse
import datetime as dt
import os
import shutil
import subprocess
import sys
from pathlib import Path
from netrc import netrc
from collections import defaultdict

# ----------------------------------------------------------------------------------------
# Script information
SCRIPT_NAME = "HEAD DOWNLOADER - HSAF PRODUCT SOIL MOISTURE H26 - REALTIME"
SCRIPT_VERSION = "3.1.1"
SCRIPT_DATE = "2025/11/18"

# =======================================================================================
# Environment / configuration
# =======================================================================================

# Mode (for info only, like H60)
SCRIPT_MODE = os.environ.get("SCRIPT_MODE", "realtime")  # not used in logic, just printed

# Data folder template (like bash DATA_FOLDER_RAW)
# Tokens: %YYYY, %MM, %DD (no %HH in H10)
LOCAL_FOLDER_RAW = os.environ.get(
    "LOCAL_FOLDER_RAW",
    os.environ.get(
        "DATA_FOLDER_RAW",
        "/share/HSAF_SM/ecmwf/nrt/h26/%YYYY/%MM/%DD/",
    ),
)

# Days back (0 = anchor date only)
DAYS = int(os.environ.get("DAYS", "7"))

# Anchor date in UTC: "today" or "YYYY-MM-DD"
START_DATE_UTC = os.environ.get("START_DATE_UTC", "today")

# Optional staging directory (like STAGING_DIR)
STAGING_DIR = os.environ.get("STAGING_DIR", "")

# Proxy
PROXY = os.environ.get("PROXY", "")

# FTP host
FTP_URL = os.environ.get("FTP_URL", "ftphsaf.meteoam.it")

# Credentials from ~/.netrc (like H60/H61 style)
NETRC_MACHINE_LABEL = os.environ.get("NETRC_MACHINE_LABEL", "ftphsaf.meteoam.it")

# Remote folder
FTP_FOLDER = os.environ.get("FTP_FOLDER", "/products/h26/h26_cur_mon_nc/")

# For header printing (same idea as FTP_FOLDER_RAW in H60)
FTP_FOLDER_RAW = os.environ.get("FTP_FOLDER_RAW", FTP_FOLDER)

# File pattern template
FILE_PATTERN_TEMPLATE = os.environ.get(
    "FILE_PATTERN_TEMPLATE", 
    "h26_%YYYY%MM%DD00_R01.nc",
)

# Connection limiting (H60-style)
CONN_LIMIT = int(os.environ.get("CONN_LIMIT", "1"))
LIMIT_RATE = int(os.environ.get("LIMIT_RATE", "0"))             # bytes/s per conn, 0 = unlimited
LIMIT_TOTAL_RATE = int(os.environ.get("LIMIT_TOTAL_RATE", "0")) # bytes/s total, 0 = unlimited

# Optional umask override (octal string, e.g. "002")
UMASK_OVERRIDE = os.environ.get("UMASK_OVERRIDE", "")

# LFTP base settings (we add connection/limits in the script builder)
LFTP_COMMON_SETTINGS = [
    "set net:timeout 30;",
    "set net:max-retries 5;",
    "set net:persist-retries 1;",
    "set xfer:clobber on;",
    "set ftp:ssl-allow true;",
    "set ftp:passive-mode true;",
]

# LFTP timeout
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

def log(msg: str) -> None:
    ts = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"[{ts}] {msg}")


def die(msg: str, rc: int = 1) -> "None":
    log(f"ERROR: {msg}")
    sys.exit(rc)


def load_netrc_creds(machine_label: str) -> tuple[str, str]:
    """Return (login, password) for the given machine label from ~/.netrc."""
    netrc_path = os.path.expanduser("~/.netrc")
    if not os.path.exists(netrc_path):
        die(f"{netrc_path} not found; create it and chmod 600.")

    try:
        n = netrc(netrc_path)
        auth = n.authenticators(machine_label)
    except Exception as exc:  # noqa: BLE001
        die(f"Failed reading {netrc_path}: {exc}")

    if auth is None or auth[0] is None or auth[2] is None:
        print(
            f' [ERROR] No credentials found in ~/.netrc for machine "{machine_label}".',
            file=sys.stderr,
        )
        print(" [HINT] Available machine labels:", file=sys.stderr)
        for host, (login, _account, _pwd) in n.hosts.items():
            print(f"   - {host} (user: {login})", file=sys.stderr)
        sys.exit(1)

    login, _, password = auth
    return login, password


def parse_anchor_date_utc(start_str: str) -> dt.date:
    """Parse START_DATE_UTC: 'today' or 'YYYY-MM-DD'."""
    s = start_str.strip().lower()
    if s in ("", "today", "now"):
        return dt.datetime.utcnow().date()
    try:
        return dt.datetime.strptime(start_str, "%Y-%m-%d").date()
    except ValueError:
        die(f"Invalid START_DATE_UTC='{START_DATE_UTC}', expected 'today' or YYYY-MM-DD.")


def build_paths_for_day(date_step: dt.date) -> tuple[str, str, str, str, str]:
    """
    Given a date, build:
      - date_step_str: YYYYMMDD
      - year_get, month_get, day_get
      - local_folder_def (final destination)
    """
    date_step_str = date_step.strftime("%Y%m%d")
    year_get = date_step.strftime("%Y")
    month_get = date_step.strftime("%m")
    day_get = date_step.strftime("%d")

    local_folder_def = (
        LOCAL_FOLDER_RAW.replace("%YYYY", year_get)
        .replace("%MM", month_get)
        .replace("%DD", day_get)
        .replace("%HH", "00")
    )

    return date_step_str, year_get, month_get, day_get, local_folder_def


def build_file_pattern(year_get: str, month_get: str, day_get: str) -> str:
    pattern = FILE_PATTERN_TEMPLATE.replace("%YYYY", year_get)
    pattern = pattern.replace("%MM", month_get)
    pattern = pattern.replace("%DD", day_get)
    return pattern


def safe_move(src: Path, dst: Path) -> None:
    """
    Safe move (across filesystems): try os.replace; fall back to copy + remove.
    """
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.replace(src, dst)
    except OSError:
        shutil.copy2(src, dst)
        os.sync()
        src.unlink(missing_ok=True)


def build_lftp_download_script(
    ftp_user: str,
    ftp_pwd: str,
    jobs: list[tuple[str, str, str]],
) -> str:
    """
    Build a single lftp script that:
    - sets common options + connection limit & bandwidth limits
    - sets cmd:fail-exit no so a failed get does not abort session
    - opens one session
    - for each (ftp_folder, local_folder, filename) in jobs:
        cd / lcd as needed, then get -c filename || echo WARN
    - closes session
    """
    lines: list[str] = []

    # Proxy
    if PROXY:
        lines.append(f"set ftp:proxy {PROXY};")
    else:
        lines.append("set ftp:proxy ;")

    # Common options
    lines.extend(LFTP_COMMON_SETTINGS)

    # Connection & bandwidth limiting
    lines.append(f"set net:connection-limit {CONN_LIMIT};")
    lines.append(f"set net:limit-rate {LIMIT_RATE};")
    lines.append(f"set net:limit-total-rate {LIMIT_TOTAL_RATE};")

    # Do not abort session on first error
    lines.append("set cmd:fail-exit no;")

    # Open one session
    lines.append(f"open -u {ftp_user},{ftp_pwd} {FTP_URL};")
    lines.append(f"echo '===== Connected to {FTP_URL} as {ftp_user} =====';")

    # Group jobs by (ftp_folder, local_folder)
    grouped: dict[tuple[str, str], list[str]] = defaultdict(list)
    for ftp_folder, local_folder, filename in jobs:
        grouped[(ftp_folder, local_folder)].append(filename)

    current_remote = None
    current_local = None

    for (ftp_folder, local_folder), files in grouped.items():
        lines.append(
            f"echo '=== SESSION BLOCK: SRC={ftp_folder} DST={local_folder} ===';"
        )
        if ftp_folder != current_remote:
            lines.append(f"cd {ftp_folder};")
            current_remote = ftp_folder
        if local_folder != current_local:
            lines.append(f"lcd {local_folder};")
            current_local = local_folder

        for fname in files:
            lines.append("echo '--- FILE DOWNLOAD ---';")
            lines.append(f"echo 'file_name: {fname}';")
            # If get fails (550 or whatever), print warning and continue
            lines.append(
                f"get -c {fname} || echo '  [WARN] Download failed for {fname}, skipping.';"
            )

    lines.append("close;")
    lines.append("quit;")

    script_str = "\n".join(lines) + "\n"
    return script_str


def run_lftp(script_text: str, purpose: str) -> int:
    """Run lftp with the provided script via stdin, with timeout + monitoring."""
    log_lftp_call(script_text)

    try:
        print(f" [LFTP] Starting {purpose} (timeout {TIMEOUT_LFTP_SECS}s)...")
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
        description=f"{SCRIPT_NAME} (Python, daily H10 product, realtime, single-session lftp)"
    )
    _ = parser.parse_args(argv)  # all config via env

    # Optional umask override
    if UMASK_OVERRIDE:
        try:
            os.umask(int(UMASK_OVERRIDE, 8))
        except ValueError:
            log(f"WARNING: Invalid UMASK_OVERRIDE='{UMASK_OVERRIDE}', ignoring.")

    # === H60-style header ===
    print(" ===================================================================================")
    print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
    print(" ==> START ...")
    print(f" ==> Mode: {SCRIPT_MODE} ; Days back: {DAYS}")
    print(f" ==> FTP Host: {FTP_URL}")
    print(f" ==> Local template: {LOCAL_FOLDER_RAW}")
    print(f" ==> FTP template:   {FTP_FOLDER_RAW}")
    print(" ===================================================================================")

    ftp_usr, ftp_pwd = load_netrc_creds(NETRC_MACHINE_LABEL)
    print(
        f" ===> INFO MACHINE -- URL: {FTP_URL} -- NETRC: {NETRC_MACHINE_LABEL} -- USER: {ftp_usr}"
    )

    anchor_date = parse_anchor_date_utc(START_DATE_UTC)
    log(f"Anchor UTC date: {anchor_date.isoformat()} ; Days back: {DAYS}")

    # JOBS: (ftp_folder, local_dir_str, filename, stage_path, target_path)
    jobs_meta: list[tuple[str, str, str, Path, Path]] = []

    # From anchor date back in time
    for i in range(DAYS + 1):
        date_step = anchor_date - dt.timedelta(days=i)
        date_step_str, year_get, month_get, day_get, target_dir_str = build_paths_for_day(
            date_step
        )
        date_iso = date_step.isoformat()
        pattern = build_file_pattern(year_get, month_get, day_get)

        target_dir = Path(target_dir_str)
        target_file = target_dir / pattern

        if STAGING_DIR:
            stage_dir = Path(STAGING_DIR.rstrip("/")) / year_get / month_get / day_get
        else:
            stage_dir = target_dir

        stage_file = stage_dir / pattern

        # Ensure directories exist
        stage_dir.mkdir(parents=True, exist_ok=True)
        target_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n ===> TIME_STEP: {date_step_str} ===> START ")
        print(f"  [INFO] Target FTP folder: {FTP_FOLDER}")
        print(f"  [INFO] Target LOCAL folder: {target_dir_str}")
        print(f"  [INFO] File pattern: {pattern}")

        # Skip if already present at final destination
        if target_file.is_file() and target_file.stat().st_size > 0:
            print(f"    FILE: {pattern} => SKIP (local exists)")
            print(f" ===> TIME_STEP: {date_step_str} ===> END ")
            continue

        # Not present locally: mark for download
        print(f"    FILE: {pattern} => DOWNLOAD (missing locally)")
        jobs_meta.append(
            (FTP_FOLDER, str(stage_dir), pattern, stage_file, target_file)
        )

        print(f" ===> TIME_STEP: {date_step_str} ===> END ")

    if not jobs_meta:
        print(" [INFO] Nothing to download (all files already present).")
        print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
        print(" ==> ... END")
        print(" ==> Bye, Bye")
        print(" ===================================================================================")
        return 0

    # Build lftp job triples for the downloader
    lftp_jobs: list[tuple[str, str, str]] = [
        (ftp_folder, local_dir_str, filename)
        for (ftp_folder, local_dir_str, filename, _stage_file, _target_file) in jobs_meta
    ]

    lftp_script = build_lftp_download_script(ftp_usr, ftp_pwd, lftp_jobs)
    rc = run_lftp(lftp_script, "single-session transfer")

    if rc == 0:
        print(" [LFTP] Session completed successfully.")
    elif rc == 124:
        print(" [LFTP] Session TIMEOUT.")
    else:
        print(f" [LFTP] Session exited with rc={rc}.")

    # Post-process: verify & move from staging if needed
    for ftp_folder, local_dir_str, filename, stage_file, target_file in jobs_meta:
        _ = ftp_folder  # unused, kept for clarity
        print(f" [POST] Checking {filename} in {local_dir_str}")
        if not stage_file.is_file() or stage_file.stat().st_size <= 0:
            print(
                f"  [WARN] File not present or empty after transfer: {stage_file}. "
                "Skipping move."
            )
            continue

        # Move to final if staging differs
        if stage_file.parent != target_file.parent:
            safe_move(stage_file, target_file)
        else:
            target_file = stage_file

        if target_file.is_file() and target_file.stat().st_size > 0:
            print(f"  [OK] Final file: {target_file}")
        else:
            print(f"  [WARN] Final verification failed for {target_file}")

    print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
    print(" ==> ... END")
    print(" ==> Bye, Bye")
    print(" ===================================================================================")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

