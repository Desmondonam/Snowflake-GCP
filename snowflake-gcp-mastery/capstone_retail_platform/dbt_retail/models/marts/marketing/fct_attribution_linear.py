"""Linear attribution as a dbt PYTHON model (runs as Snowpark inside Snowflake).

Every touch before an order gets an equal share: credit = 1 / number_of_touches.
Nothing here leaves Snowflake: `dbt.ref()` returns a lazy Snowpark DataFrame, the
transformations compile to SQL, and dbt saves the result as a table.

Why Python for this one? It's simple enough for SQL too (compare with the time-decay
model), but it is the template for logic that IS easier in Python: Markov-chain or
Shapley attribution, ML features, calling a Python library.
"""
import snowflake.snowpark.functions as F
from snowflake.snowpark import Window


def model(dbt, session):
    dbt.config(
        materialized="table",
        snowflake_warehouse="TRANSFORM_WH",
        python_version="3.11",
    )

    touches = dbt.ref("int_order_touchpoints")
    per_order = Window.partition_by("ORDER_ID")

    return (
        touches
        .with_column("N_TOUCHES", F.count(F.lit(1)).over(per_order))
        .with_column("CREDIT", (F.lit(1.0) / F.col("N_TOUCHES")).cast("NUMBER(10,6)"))
        .with_column("ATTRIBUTED_REVENUE", (F.col("CREDIT") * F.col("ORDER_NET")).cast("NUMBER(14,2)"))
        .with_column("ATTRIBUTION_MODEL", F.lit("linear"))
        .select(
            "ORDER_ID", "CUSTOMER_ID", "ORDERED_AT", "TOUCHPOINT_ID", "TOUCHED_AT",
            "CHANNEL", "CAMPAIGN_ID", "CREDIT", "ATTRIBUTED_REVENUE", "ATTRIBUTION_MODEL",
        )
    )
