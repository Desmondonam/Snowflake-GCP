"""Create or drop the zero-copy clone environment for a CI run.

    python ci/clone_env.py create --suffix PR_42
    python ci/clone_env.py drop   --suffix PR_42

Clones RETAIL_STAGING and RETAIL_MARTS to RETAIL_STAGING_PR_42 / RETAIL_MARTS_PR_42 in seconds
(metadata only), then suspends any dynamic tables in the clones so CI never pays for refreshes.
dbt's `ci` target (profiles.yml + generate_database_name) builds into exactly these databases.

Connection comes from the same env vars as dbt: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER,
SNOWFLAKE_PRIVATE_KEY_PATH, SNOWFLAKE_PRIVATE_KEY_PASSPHRASE, SNOWFLAKE_ROLE, SNOWFLAKE_WAREHOUSE.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

import snowflake.connector

SOURCE_DATABASES = ["RETAIL_STAGING", "RETAIL_MARTS"]


def connect():
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="SNOWFLAKE_JWT",
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        private_key_file_pwd=os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None,
        role=os.getenv("SNOWFLAKE_ROLE", "RETAIL_ENGINEER"),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", "TRANSFORM_WH"),
        session_parameters={"QUERY_TAG": "ci_clone_env"},
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["create", "drop"])
    parser.add_argument("--suffix", required=True, help="e.g. PR_42")
    args = parser.parse_args()

    suffix = args.suffix.upper()
    if not re.fullmatch(r"[A-Z0-9_]{1,40}", suffix):
        print(f"invalid suffix {suffix!r}: use letters, digits and underscores only", file=sys.stderr)
        return 2

    with connect() as conn:
        cur = conn.cursor()
        for db in SOURCE_DATABASES:
            clone = f"{db}_{suffix}"
            if args.action == "create":
                cur.execute(f"CREATE OR REPLACE DATABASE {clone} CLONE {db} COMMENT = 'CI clone for {suffix}'")
                print(f"created {clone} (zero-copy clone of {db})")
                for row in cur.execute(f"SHOW DYNAMIC TABLES IN DATABASE {clone}").fetchall():
                    # SHOW DYNAMIC TABLES columns: created_on, name, database_name, schema_name, ...
                    name, schema = row[1], row[3]
                    cur.execute(f"ALTER DYNAMIC TABLE {clone}.{schema}.{name} SUSPEND")
                    print(f"  suspended dynamic table {clone}.{schema}.{name}")
            else:
                cur.execute(f"DROP DATABASE IF EXISTS {clone}")
                print(f"dropped {clone}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
