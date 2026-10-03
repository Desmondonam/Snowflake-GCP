"""
### retail_daily — RetailOne nightly pipeline (the "slow speed" of Capstone 5)

For one **business date** (default: the day before the run):

1. `wait_for_pos_files` — every store that appears in the POS control file has its sales lines in RAW
   (Snowpipe loads them; this sensor waits up to 2 h, rescheduling instead of holding a worker slot)
2. `dbt_source_freshness` — informational, runs in parallel; a failure alerts but doesn't block
3. `dbt_build` — `dbt build --target prod` (models + snapshots + tests), reconciliation excluded
4. `dbt_reconciliation` — `dbt test -s tag:reconciliation`: warehouse vs POS Z-report within 0.5% per store-day
5. `publish_summary` — posts the result to Slack (or logs it when no webhook is configured)

Any task failure triggers `notify_failure` (Slack / log).

Trigger manually for a specific day: **Trigger DAG → Run with config** → `{"business_date": "2026-10-02"}`.

Airflow 3 note: for cron schedules the logical date is the run time itself, so "yesterday" is
`macros.ds_add(ds, -1)` — not `ds` as in Airflow 2's data-interval semantics.
"""
from __future__ import annotations

import json
import logging
import os
from datetime import timedelta

import pendulum
import requests
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.common.sql.sensors.sql import SqlSensor
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG, Param, task

log = logging.getLogger(__name__)

SNOWFLAKE_CONN_ID = "snowflake_default"
DBT_DIR = "/usr/local/airflow/include/dbt_retail"
DBT_BIN = "/usr/local/airflow/dbt_venv/bin/dbt"
BUSINESS_DATE = "{{ params.business_date or macros.ds_add(ds, -1) }}"


def post_to_slack(text: str) -> None:
    url = os.getenv("SLACK_WEBHOOK_URL")
    if not url:
        log.info("SLACK_WEBHOOK_URL not set; message would have been:\n%s", text)
        return
    resp = requests.post(url, json={"text": text}, timeout=10)
    resp.raise_for_status()


def notify_failure(context) -> None:
    ti = context["task_instance"]
    post_to_slack(
        f":red_circle: RetailOne `{ti.dag_id}` task `{ti.task_id}` failed "
        f"(run {context.get('run_id')}, try {ti.try_number}). Check the Airflow logs."
    )


dbt_env = {
    # dbt reads its connection from these (same names as the repo .env); DBT_* keep logs tidy
    "DBT_PROFILES_DIR": DBT_DIR,
    "DBT_SEND_ANONYMOUS_USAGE_STATS": "false",
}

with DAG(
    dag_id="retail_daily",
    description="RetailOne nightly: arrival check → dbt build → reconciliation → notify",
    schedule="0 4 * * *",  # 04:00 UTC = 07:00 Nairobi / Doha, after stores have closed and uploaded
    start_date=pendulum.datetime(2026, 10, 1, tz="UTC"),
    catchup=False,
    max_active_runs=1,
    default_args={
        "owner": "data-platform",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
        "on_failure_callback": notify_failure,
    },
    params={
        "business_date": Param(None, type=["null", "string"], description="YYYY-MM-DD; empty = yesterday"),
    },
    tags=["retailone", "daily", "dbt"],
    doc_md=__doc__,
) as dag:

    wait_for_pos_files = SqlSensor(
        task_id="wait_for_pos_files",
        conn_id=SNOWFLAKE_CONN_ID,
        sql=f"""
            with expected as (
                select count(*) as n from RETAIL_RAW.POS.CONTROL_TOTALS
                where business_date = '{BUSINESS_DATE}'
            ),
            arrived as (
                select count(distinct store_id) as n from RETAIL_RAW.POS.SALES_LINES
                where sold_at::date = '{BUSINESS_DATE}'
            )
            select e.n > 0 and a.n >= e.n from expected e, arrived a
        """,
        mode="reschedule",
        poke_interval=300,
        timeout=2 * 60 * 60,
    )

    dbt_source_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=f"cd {DBT_DIR} && {DBT_BIN} deps --quiet && {DBT_BIN} source freshness --target prod",
        env=dbt_env,
        append_env=True,
        retries=0,
    )

    dbt_build = BashOperator(
        task_id="dbt_build",
        bash_command=(
            f"cd {DBT_DIR} && {DBT_BIN} deps --quiet && "
            f"{DBT_BIN} build --target prod --exclude tag:reconciliation"
        ),
        env=dbt_env,
        append_env=True,
        execution_timeout=timedelta(hours=1),
    )

    dbt_reconciliation = BashOperator(
        task_id="dbt_reconciliation",
        bash_command=f"cd {DBT_DIR} && {DBT_BIN} test --target prod --select tag:reconciliation",
        env=dbt_env,
        append_env=True,
        retries=0,  # a mismatch won't fix itself by retrying; a human (or a late file) must act
    )

    reconciliation_summary = SQLExecuteQueryOperator(
        task_id="reconciliation_summary",
        conn_id=SNOWFLAKE_CONN_ID,
        sql=f"""
            select status, count(*) as store_days, round(sum(pos_net_amount), 2) as pos_net,
                   round(sum(wh_net_amount), 2) as wh_net
            from RETAIL_MARTS.OPS.RPT_POS_RECONCILIATION
            where business_date = '{BUSINESS_DATE}'
            group by status order by status
        """,
        trigger_rule="all_done",  # report even when the reconciliation test failed
    )

    @task(trigger_rule="all_done")
    def publish_summary(rows, business_date: str) -> None:
        lines = [f"*RetailOne daily* — business date {business_date}"]
        for status, store_days, pos_net, wh_net in rows or []:
            icon = ":white_check_mark:" if status == "OK" else ":warning:"
            lines.append(f"{icon} {status}: {store_days} store-days · POS {pos_net} · warehouse {wh_net}")
        post_to_slack("\n".join(lines))

    summary = publish_summary(reconciliation_summary.output, BUSINESS_DATE)

    wait_for_pos_files >> dbt_build >> dbt_reconciliation >> reconciliation_summary >> summary
    wait_for_pos_files >> dbt_source_freshness
