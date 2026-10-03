"""Deploy the Snowflake objects that neither Terraform nor dbt owns, in a fixed order.

    python capstone_retail_platform/snowflake/deploy.py --phase pre        # before data: RAW stage, formats, tables, pipes
    python capstone_retail_platform/snowflake/deploy.py --phase backfill   # one-off: COPY files already in GCS into RAW
    python capstone_retail_platform/snowflake/deploy.py --phase post       # after `dbt build --target prod`: realtime + governance
    python capstone_retail_platform/snowflake/deploy.py --phase post --dry-run

Every script is idempotent, so re-running a phase is safe. Scripts switch roles themselves
(USE ROLE …), so connect as your own user (it holds SYSADMIN/SECURITYADMIN/ACCOUNTADMIN).
A production team would use schemachange or Snowflake's Git integration for the same job;
this keeps the mechanics visible.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import snowflake.connector
from dotenv import load_dotenv

REPO = Path(__file__).resolve().parents[2]
load_dotenv(REPO / ".env")

PHASES: dict[str, list[str]] = {
    "pre": [
        "capstone_retail_platform/snowflake/migrations/V01__raw_common.sql",
        "stage_02_ingestion/capstone_02_raw_layer.sql",
    ],
    "backfill": [
        "stage_02_ingestion/capstone_02_backfill_copy.sql",
    ],
    "post": [
        "stage_05_orchestration/02_stream_task_pipeline.sql",
        "capstone_retail_platform/snowflake/migrations/V04__live_stock.sql",
        "stage_07_quality_governance/01_rbac_roles.sql",
        "stage_07_quality_governance/02_tags_and_masking.sql",
        "stage_07_quality_governance/03_row_access_policy.sql",
    ],
}


def connect():
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="SNOWFLAKE_JWT",
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        private_key_file_pwd=os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None,
        session_parameters={"QUERY_TAG": "deploy_py"},
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--phase", required=True, choices=list(PHASES))
    parser.add_argument("--dry-run", action="store_true", help="list the scripts without running them")
    args = parser.parse_args()

    scripts = [REPO / p for p in PHASES[args.phase]]
    missing = [s for s in scripts if not s.exists()]
    if missing:
        print("missing scripts:", *missing, sep="\n  ")
        return 2
    for s in scripts:
        if "YOUR_PROJECT_ID" in s.read_text(encoding="utf-8"):
            print(f"{s.relative_to(REPO)} still contains YOUR_PROJECT_ID — do the find/replace first (root README §4)")
            return 2

    print(f"Phase '{args.phase}': {len(scripts)} script(s)")
    if args.dry_run:
        for s in scripts:
            print("  would run", s.relative_to(REPO))
        return 0

    with connect() as conn:
        for script in scripts:
            print(f"\n=== {script.relative_to(REPO)}")
            sql = script.read_text(encoding="utf-8")
            try:
                for cur in conn.execute_string(sql, remove_comments=True):
                    first_line = (cur.query or "").strip().splitlines()[0][:100] if cur.query else ""
                    print(f"  ok  {first_line}")
            except snowflake.connector.errors.ProgrammingError as exc:
                print(f"  FAILED: {exc.msg}\n  (query id {exc.sfqid}) — fix it and re-run the phase; scripts are idempotent")
                return 1
    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
