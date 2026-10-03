"""Check that the local environment is ready for the course.

Run from the repo root with the virtual environment active:
    python 00_setup/check_env.py

Each check prints OK, SKIP or FAIL with a hint. Fix FAIL lines before moving on.
"""
from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(REPO_ROOT / ".env")

results: list[tuple[str, str, str]] = []


def record(name: str, status: str, detail: str = "") -> None:
    results.append((name, status, detail))
    print(f"[{status:4}] {name}" + (f"  — {detail}" if detail else ""))


def check_python() -> None:
    v = sys.version_info
    if (3, 10) <= (v.major, v.minor) <= (3, 12):
        record("Python version", "OK", f"{v.major}.{v.minor}")
    else:
        record("Python version", "FAIL", f"{v.major}.{v.minor}; use 3.11 (3.10–3.12 supported here)")


def check_packages() -> None:
    for module in [
        "snowflake.connector",
        "snowflake.snowpark",
        "dbt.version",
        "google.cloud.storage",
        "google.cloud.pubsub_v1",
        "faker",
        "pandas",
        "pyarrow",
    ]:
        try:
            importlib.import_module(module)
            record(f"import {module}", "OK")
        except Exception as exc:  # noqa: BLE001
            record(f"import {module}", "FAIL", f"{exc}; run pip install -r requirements.txt")


def check_env_vars() -> bool:
    required = [
        "SNOWFLAKE_ACCOUNT",
        "SNOWFLAKE_USER",
        "SNOWFLAKE_PRIVATE_KEY_PATH",
        "GCP_PROJECT_ID",
        "GCS_LANDING_BUCKET",
    ]
    ok = True
    for var in required:
        value = os.getenv(var, "")
        if not value or "ORGNAME" in value or "YOUR_PROJECT_ID" in value:
            record(f"env {var}", "FAIL", "missing or still a placeholder in .env")
            ok = False
        else:
            record(f"env {var}", "OK")
    key_path = Path(os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH", ""))
    if key_path.is_file():
        record("private key file", "OK", str(key_path))
    else:
        record("private key file", "FAIL", f"not found: {key_path}")
        ok = False
    return ok


def check_snowflake() -> None:
    import snowflake.connector

    try:
        conn = snowflake.connector.connect(
            account=os.environ["SNOWFLAKE_ACCOUNT"],
            user=os.environ["SNOWFLAKE_USER"],
            authenticator="SNOWFLAKE_JWT",
            private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
            private_key_file_pwd=os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None,
            login_timeout=30,
        )
    except Exception as exc:  # noqa: BLE001
        record("Snowflake login", "FAIL", str(exc).splitlines()[0])
        return
    with conn:
        cur = conn.cursor()
        user, role, region, version = cur.execute(
            "select current_user(), current_role(), current_region(), current_version()"
        ).fetchone()
        record("Snowflake login", "OK", f"user={user} role={role} region={region} version={version}")
        if not str(region).upper().startswith("GCP_"):
            record("Snowflake cloud", "FAIL", "account is not on GCP; Snowpipe auto-ingest from GCS needs a GCP account")
        else:
            record("Snowflake cloud", "OK", region)
        roles = {r[1] for r in cur.execute("show roles").fetchall()}
        if "RETAIL_ENGINEER" in roles:
            record("Capstone 1 roles exist", "OK")
        else:
            record("Capstone 1 roles exist", "SKIP", "created in stage_01 capstone")


def check_gcs() -> None:
    try:
        from google.cloud import storage

        client = storage.Client(project=os.environ["GCP_PROJECT_ID"])
        bucket = client.lookup_bucket(os.environ["GCS_LANDING_BUCKET"])
    except Exception as exc:  # noqa: BLE001
        record("GCS access", "FAIL", f"{str(exc).splitlines()[0]}; run gcloud auth application-default login")
        return
    if bucket is None:
        record("GCS landing bucket", "SKIP", "not created yet (GCP track G1)")
    else:
        record("GCS landing bucket", "OK", f"gs://{bucket.name} ({bucket.location})")


def main() -> int:
    print(f"Repo root: {REPO_ROOT}\n")
    check_python()
    check_packages()
    if check_env_vars():
        check_snowflake()
        check_gcs()
    failed = [r for r in results if r[1] == "FAIL"]
    print(f"\n{len(results) - len(failed)} passed/skipped, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
