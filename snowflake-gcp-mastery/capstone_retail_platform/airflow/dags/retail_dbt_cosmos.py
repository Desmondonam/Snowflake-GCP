"""
### retail_dbt_cosmos — the same dbt project, one Airflow task per dbt model (optional)

Astronomer Cosmos reads the dbt project and renders every model (and its tests) as its own
Airflow task, so you can see, retry and time each model individually in the Airflow UI.
`retail_daily` runs dbt as ONE task (simpler, faster to start); this DAG shows the alternative.

Unscheduled: trigger it manually after a `new-day` upload.
"""
from __future__ import annotations

from pathlib import Path

import pendulum
from cosmos import DbtDag, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig

DBT_DIR = Path("/usr/local/airflow/include/dbt_retail")

retail_dbt_cosmos = DbtDag(
    dag_id="retail_dbt_cosmos",
    project_config=ProjectConfig(DBT_DIR),
    profile_config=ProfileConfig(
        profile_name="dbt_retail",
        target_name="prod",
        profiles_yml_filepath=DBT_DIR / "profiles.yml",  # reads SNOWFLAKE_* env vars
    ),
    execution_config=ExecutionConfig(dbt_executable_path="/usr/local/airflow/dbt_venv/bin/dbt"),
    render_config=RenderConfig(exclude=["tag:reconciliation"]),
    operator_args={"install_deps": True},
    schedule=None,
    start_date=pendulum.datetime(2026, 10, 1, tz="UTC"),
    catchup=False,
    tags=["retailone", "dbt", "cosmos"],
    doc_md=__doc__,
)
