"""Shared helper: open a Snowpark session from the repo's .env (key-pair auth).

Every lesson does:   from _session import get_session
Run lessons from this folder:   cd stage_04_dbt_snowpark/snowpark ; python 01_dataframes.py
"""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from snowflake.snowpark import Session

load_dotenv(Path(__file__).resolve().parents[2] / ".env")


def get_session(role: str = "RETAIL_ENGINEER", warehouse: str = "TRANSFORM_WH") -> Session:
    params = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "authenticator": "SNOWFLAKE_JWT",
        "private_key_file": os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        "private_key_file_pwd": os.getenv("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None,
        "role": role,
        "warehouse": warehouse,
        "database": "RETAIL_LAB",
        "schema": "SNOWPARK",
    }
    session = Session.builder.configs(params).create()
    session.sql("create schema if not exists RETAIL_LAB.SNOWPARK").collect()
    session.use_schema("RETAIL_LAB.SNOWPARK")
    session.query_tag = "snowpark_lessons"
    return session
