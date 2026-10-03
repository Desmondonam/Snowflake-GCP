"""Snowpark lesson 03 — a Python STORED PROCEDURE: RFM customer segmentation.

RFM = Recency (days since last purchase), Frequency (baskets), Monetary (net spend).
Each scored 1–5 by quintile; segments like "Champions" or "At risk" feed marketing.

A stored procedure bundles logic + writes, runs entirely in Snowflake, and can be called from
SQL, a Task (Stage 5) or Airflow:   CALL RETAIL_LAB.SNOWPARK.BUILD_RFM('RETAIL_LAB.SNOWPARK.CUSTOMER_RFM');

Run:  cd stage_04_dbt_snowpark/snowpark ; python 03_stored_procedure_rfm.py
"""
import snowflake.snowpark.functions as F
from snowflake.snowpark import Session, Window

from _session import get_session


def build_rfm(session: Session, target_table: str) -> str:
    lines = session.table("RETAIL_RAW.POS.SALES_LINES").filter(F.col("LOYALTY_ID").is_not_null())
    as_of = lines.select(F.max(F.to_date("SOLD_AT"))).collect()[0][0]

    per_customer = (
        lines
        .with_column("NET", F.col("QTY") * F.col("UNIT_PRICE") - F.col("DISCOUNT"))
        .group_by("LOYALTY_ID")
        .agg(
            F.datediff("day", F.max(F.to_date("SOLD_AT")), F.lit(as_of)).alias("RECENCY_DAYS"),
            F.count_distinct("TRANSACTION_ID").alias("FREQUENCY"),
            F.sum("NET").alias("MONETARY"),
        )
    )

    scored = (
        per_customer
        # low recency is GOOD, so order descending for R; high F and M are good
        .with_column("R", F.ntile(5).over(Window.order_by(F.col("RECENCY_DAYS").desc())))
        .with_column("F", F.ntile(5).over(Window.order_by("FREQUENCY")))
        .with_column("M", F.ntile(5).over(Window.order_by("MONETARY")))
        .with_column(
            "SEGMENT",
            F.when((F.col("R") >= 4) & (F.col("F") >= 4) & (F.col("M") >= 4), F.lit("Champions"))
             .when((F.col("R") <= 2) & (F.col("M") >= 4), F.lit("At risk - high value"))
             .when((F.col("R") >= 4) & (F.col("F") <= 2), F.lit("New / promising"))
             .when(F.col("R") <= 2, F.lit("Hibernating"))
             .otherwise(F.lit("Loyal / needs attention")),
        )
        .with_column("AS_OF_DATE", F.lit(as_of))
    )
    scored.write.save_as_table(target_table, mode="overwrite")
    return f"{target_table}: {session.table(target_table).count()} customers scored as of {as_of}"


if __name__ == "__main__":
    session = get_session()
    session.sql("create stage if not exists RETAIL_LAB.SNOWPARK.SPROC_STAGE").collect()

    # Register as a permanent stored procedure (the function body is pickled to the stage)
    session.sproc.register(
        build_rfm,
        name="RETAIL_LAB.SNOWPARK.BUILD_RFM",
        packages=["snowflake-snowpark-python"],
        is_permanent=True,
        stage_location="@RETAIL_LAB.SNOWPARK.SPROC_STAGE",
        replace=True,
        execute_as="caller",
    )

    # Call it like SQL would
    print(session.call("RETAIL_LAB.SNOWPARK.BUILD_RFM", "RETAIL_LAB.SNOWPARK.CUSTOMER_RFM"))
    session.sql("""
        select segment, count(*) as customers, round(avg(monetary), 2) as avg_spend
        from RETAIL_LAB.SNOWPARK.CUSTOMER_RFM group by 1 order by 3 desc
    """).show()
    session.close()
