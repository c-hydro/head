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
SCRIPT_NAME = "HEAD DOWNLOADER - HSAF PRODUCT PRECIPITATION H61"
SCRIPT_VERSION = "3.3.1"
SCRIPT_DATE = "2025/11/18" 

# === User settings (H61) ===============================================================

# .netrc machine label to use (e.g., "ftphsaf.meteoam.it")
NETRC_MACHINE_LABEL = os.environ.get("NETRC_MACHINE_LABEL", "ftphsaf.meteoam.it")

# Actual FTP host
FTP_URL = os.environ.get("FTP_URL", "ftphsaf.meteoam.it")

# Optional proxy (or empty)
PROXY = os.environ.get("PROXY", "")

# Mode: 'realtime' or 'history'
SCRIPT_MODE = os.environ.get("SCRIPT_MODE", "realtime")  # "realtime" or "history"

# Days back inclusive (0 = today only)
DAYS = int(os.environ.get("DAYS", "1"))

# Local path pattern (H61 uses hourly dirs: %HH)
LOCAL_FOLDER_RAW = os.environ.get(
    "LOCAL_FOLDER_RAW",
    "/share/HSAF_PRECIPITATION/nrt/h61/%YYYY/%MM/%DD/%HH/",
)

# Remote folder template (H61)
if SCRIPT_MODE == "realtime":
    FTP_FOLDER_RAW = os.environ.get(
        "FTP_FOLDER_RAW", "/products/h61/h61_cur_mon_nc/"
    )
else:
    FTP_FOLDER_RAW = os.environ.get(
        "FTP_FOLDER_RAW", "/hsaf_archive/h61/%YYYY/%MM/%DD/%HH/"
    )

# Safety lag for current hour (minutes)
SAFETY_LAG_MIN = int(os.environ.get("SAFETY_LAG_MIN", "5"))

# LFTP common settings (no cmd:fail-exit here, handled per-use)
LFTP_COMMON_SETTINGS = [
    "set net:timeout 30;",
    "set net:max-retries 3;",
    "set net:reconnect-interval-base 5;",
    "set net:reconnect-interval-max 20;",
    "set ftp:passive-mode yes;",
    "set xfer:clobber on;",
]

# LFTP timeout for main session (and for small checks)
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


def build_paths_for_hour(date_step: dt.date, hour: int) -> tuple[str, str, str, str]:
    """
    Given a date (date_step) and hour (0-23), build:
      - date_step_str: YYYYMMDD
      - hour_get: HH
      - ftp_folder_def
      - local_folder_def
    """
    date_step_str = date_step.strftime("%Y%m%d")
    year_get = date_step.strftime("%Y")
    month_get = date_step.strftime("%m")
    day_get = date_step.strftime("%d")
    hour_get = f"{hour:02d}"

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


def is_synoptic_hour(hour: int) -> bool:
    """Return True if hour is 00, 06, 12, 18."""
    return hour in (0, 6, 12, 18)


def remote_dir_exists(ftp_user: str, ftp_pwd: str, ftp_folder: str) -> bool:
    """
    Check if a remote directory exists by trying `cd` into it via a short lftp call.
    Returns True if cd succeeds, False otherwise.
    """
    if PROXY:
        proxy_cmd = f"set ftp:proxy {PROXY}; "
    else:
        proxy_cmd = "set ftp:proxy ; "

    cmd = [
        "lftp",
        "-u",
        f"{ftp_user},{ftp_pwd}",
        FTP_URL,
        "-e",
        proxy_cmd
        + "set cmd:fail-exit yes; "
        + "; ".join(LFTP_COMMON_SETTINGS)
        + f"; cd {ftp_folder}; bye;"
    ]
    try:
        result = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=TIMEOUT_LFTP_SECS,
        )
    except subprocess.TimeoutExpired:
        print(f"  [WARN] Timeout while checking remote dir {ftp_folder}", file=sys.stderr)
        return False

    if result.returncode != 0:
        return False

    return True


def build_lftp_download_script(
    ftp_user: str,
    ftp_pwd: str,
    jobs: list[tuple[str, str, str]],
) -> str:
    """
    Build a single lftp script that:
    - sets common options
    - sets cmd:fail-exit no so a failed get does not abort session
    - opens one session
    - for each (ftp_folder, local_folder, filename) in jobs:
        cd / lcd as needed, then get -c filename || echo WARN
    - closes session
    """
    lines: list[str] = []

    # Proxy + common settings
    if PROXY:
        lines.append(f"set ftp:proxy {PROXY};")
    else:
        lines.append("set ftp:proxy ;")
    lines.extend(LFTP_COMMON_SETTINGS)
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


def build_lftp_plan_script(
    ftp_user: str,
    ftp_pwd: str,
    jobs_meta: list[tuple[str, str, str, bool]],
) -> str:
    """
    Build a single lftp script for PLAN mode that:
    - checks remote existence of each filename via `cls`
    - prints a block for each file.
    jobs_meta: list of (ftp_folder, local_folder, filename, local_exists)
    """
    lines: list[str] = []

    # Proxy + common settings
    if PROXY:
        lines.append(f"set ftp:proxy {PROXY};")
    else:
        lines.append("set ftp:proxy ;")
    lines.extend(LFTP_COMMON_SETTINGS)
    # In plan mode we DO NOT want a single failure to abort all checks
    lines.append("set cmd:fail-exit no;")

    # Open one session
    lines.append(f"open -u {ftp_user},{ftp_pwd} {FTP_URL};")
    lines.append(f"echo '===== Connected to {FTP_URL} as {ftp_user} =====';")

    # Group jobs by (ftp_folder, local_folder)
    grouped: dict[tuple[str, str], list[tuple[str, bool]]] = defaultdict(list)
    for ftp_folder, local_folder, filename, local_exists in jobs_meta:
        grouped[(ftp_folder, local_folder)].append((filename, local_exists))

    current_remote = None
    current_local = None

    for (ftp_folder, local_folder), files in grouped.items():
        lines.append(f"echo '  [DIR OK] {ftp_folder}';")
        if ftp_folder != current_remote:
            lines.append(f"cd {ftp_folder};")
            current_remote = ftp_folder
        if local_folder != current_local:
            lines.append(f"lcd {local_folder};")
            current_local = local_folder

        for fname, local_exists in files:
            lines.append("echo '--- FILE ---';")
            lines.append(f"echo 'file_name: {fname}';")
            lines.append(f"echo 'src_folder: {ftp_folder}';")
            lines.append(f"echo 'dst_folder: {local_folder}';")
            lines.append("echo 'dir_ok: YES';")

            if local_exists:
                lines.append("echo 'status: SKIP (exists locally)';")
                lines.append(
                    f"if (cls -1 {fname}) "
                    "echo 'remote: AVAILABLE'; "
                    "else "
                    "echo 'remote: NOT_FOUND'; "
                    "fi;"
                )
                lines.append("echo 'action: SKIP (already downloaded)';")
            else:
                lines.append("echo 'status: NEEDED';")
                lines.append(
                    f"if (cls -1 {fname}) "
                    "echo 'remote: AVAILABLE'; "
                    "else "
                    "echo 'remote: NOT_FOUND'; "
                    "fi;"
                )
                lines.append(
                    f"if (cls -1 {fname}) "
                    "echo 'action: DOWNLOAD'; "
                    "else "
                    "echo 'action: SKIP (remote missing)'; "
                    "fi;"
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
        description=f"{SCRIPT_NAME} (Python, single-session lftp, H61 with synoptic hours)"
    )
    parser.add_argument(
        "-p", "--plan", action="store_true",
        help="Plan mode: only list decisions (SKIP/DOWNLOAD), do not actually download files."
    )
    _args = parser.parse_args(argv)
    plan_mode = _args.plan

    print(" ===================================================================================")
    print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
    print(" ==> START ...")
    print(f" ==> Mode: {SCRIPT_MODE} ; Days back: {DAYS}")
    print(f" ==> FTP Host: {FTP_URL}")
    print(f" ==> Local template: {LOCAL_FOLDER_RAW}")
    print(f" ==> FTP template:   {FTP_FOLDER_RAW}")
    if plan_mode:
        print(" ==> PLAN MODE: ON (no downloads)")
    print(" ===================================================================================")

    ftp_usr, ftp_pwd = load_netrc_creds(NETRC_MACHINE_LABEL)
    print(f" ===> INFO MACHINE -- URL: {FTP_URL} -- NETRC: {NETRC_MACHINE_LABEL} -- USER: {ftp_usr}")

    now = dt.datetime.now()
    now_day_str = now.strftime("%Y%m%d")
    now_hour = int(now.strftime("%H"))
    now_min = int(now.strftime("%M"))
    today = now.date()

    download_jobs: list[tuple[str, str, str]] = []
    plan_jobs_meta: list[tuple[str, str, str, bool]] = []

    # -----------------------------------------------------------------------------------
    # Outer loop: days back FROM NOW TO PAST (today -> today-1 -> ... -> today-DAYS)
    # -----------------------------------------------------------------------------------
    for day_offset in range(DAYS + 1):
        date_step = today - dt.timedelta(days=day_offset)
        date_step_str = date_step.strftime("%Y%m%d")

        print(f"\n ===> TIME_STEP: {date_step_str} ===> START ")

        # Hours from "now" back to 0 for today; 23..0 for previous days
        if SCRIPT_MODE == "realtime":
            if date_step_str == now_day_str:
                count_start = now_hour
                count_end = 0
            else:
                count_start = 23
                count_end = 0
        else:
            count_start = 23
            count_end = 0

        # Loop hours descending (now -> past)
        for hour in range(count_start, count_end - 1, -1):
            hour_get_str = f"{hour:02d}"
            print(f" ===> HOUR_STEP: {hour_get_str} ===> START ")

            # SAFETY LAG: for realtime current day + current hour, skip if too early
            if (
                SCRIPT_MODE == "realtime"
                and date_step_str == now_day_str
                and hour == now_hour
                and now_min < SAFETY_LAG_MIN
            ):
                print(
                    f"  [INFO] Current hour {hour_get_str} has not passed safety lag "
                    f"({SAFETY_LAG_MIN}m). Skipping this hour."
                )
                print(f" ===> HOUR_STEP: {hour_get_str} ===> END ")
                continue

            # Build FTP and local folders
            date_step_str2, hour_get, ftp_folder_def, local_folder_def = build_paths_for_hour(
                date_step, hour
            )

            local_dir = Path(local_folder_def)
            local_dir.mkdir(parents=True, exist_ok=True)

            print(f"  [INFO] Target FTP folder: {ftp_folder_def}")
            print(f"  [INFO] Target LOCAL folder: {local_folder_def}")

            # Check remote source folder existence
            if not remote_dir_exists(ftp_usr, ftp_pwd, ftp_folder_def):
                print(f"  [WARN] Remote dir does not exist: {ftp_folder_def} – skipping this hour.")
                print(f" ===> HOUR_STEP: {hour_get_str} ===> END ")
                continue

            # ----------------------------------------------------------------------
            # Build expected filenames for H61 at this hour
            #   - always 01_fdk
            #   - plus 24_fdk at synoptic hours (00,06,12,18)
            # ----------------------------------------------------------------------
            expected_files: list[str] = []
            expected_files.append(f"h61_{date_step_str2}_{hour_get}00_01_fdk.nc.gz")
            if is_synoptic_hour(hour):
                expected_files.append(f"h61_{date_step_str2}_{hour_get}00_24_fdk.nc.gz")

            print("  [INFO] Expected files:")
            for ef in expected_files:
                print(f"         - {ef}")

            # Iterate expected files
            for ftp_file in expected_files:
                local_path = local_dir / ftp_file
                local_exists = local_path.is_file() and local_path.stat().st_size > 0

                if local_exists:
                    print(f"    FILE: {ftp_file} => SKIP (local exists)")
                else:
                    print(f"    FILE: {ftp_file} => DOWNLOAD (missing locally)")

                # Plan mode: always push to metadata to check remote via lftp
                plan_jobs_meta.append((ftp_folder_def, local_folder_def, ftp_file, local_exists))

                # Real mode: only missing files become download jobs
                if not plan_mode and not local_exists:
                    download_jobs.append((ftp_folder_def, local_folder_def, ftp_file))

            print(f" ===> HOUR_STEP: {hour_get_str} ===> END ")

        print(f" ===> TIME_STEP: {date_step_str} ===> END ")

    # PLAN MODE: run a single lftp to check remote files, but do not download
    if plan_mode:
        if not plan_jobs_meta:
            print(" [PLAN] Nothing to check (no eligible hours / days).")
            print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
            print(" ==> ... END")
            print(" ==> Bye, Bye")
            print(" ===================================================================================")
            return 0

        plan_script = build_lftp_plan_script(ftp_usr, ftp_pwd, plan_jobs_meta)
        rc = run_lftp(plan_script, "single-session (plan-mode)")

        if rc == 0:
            print(" [LFTP] Plan session completed successfully.")
        elif rc == 124:
            print(" [LFTP] Plan session TIMEOUT.")
        else:
            print(f" [LFTP] Plan session exited with rc={rc}.")

        print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
        print(" ==> ... END")
        print(" ==> Bye, Bye")
        print(" ===================================================================================")
        return rc

    # NORMAL MODE: actual download
    if not download_jobs:
        print(" [INFO] Nothing to download (all files already present / no remote dirs / no eligible hours).")
        print(f" ==> {SCRIPT_NAME} (Version: {SCRIPT_VERSION} Release_Date: {SCRIPT_DATE})")
        print(" ==> ... END")
        print(" ==> Bye, Bye")
        print(" ===================================================================================")
        return 0

    # Build and run single lftp session for all DOWNLOAD jobs
    lftp_script = build_lftp_download_script(ftp_usr, ftp_pwd, download_jobs)
    rc = run_lftp(lftp_script, "single-session transfer")

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

