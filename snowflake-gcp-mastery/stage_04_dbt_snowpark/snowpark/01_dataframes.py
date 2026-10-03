"""Snowpark lesson 01 — DataFrames that run INSIDE Snowflake.

Key ideas
  * A Snowpark DataFrame is a lazy description of a query. Nothing runs until an ACTION:
    .collect(), .show(), .count(), .to_pandas(), .save_as_table()
  * Your Python builds SQL; Snowflake's warehouse does the work. Data never comes to your laptop
    unless you ask for it (collect / to_pandas) — so never to_pandas() 100M rows.

Run:  cd stage_04_dbt_snowpark/snowpark ; python 01_dataframes.py
"""
import snowflake.snowpark.functions as F
from snowflake.snowpark import Window

from _session import get_session

session = get_session()

# 1. A table as a DataFrame (no data moved yet)
lines = session.table("RETAIL_RAW.POS.SALES_LINES")
print("columns:", lines.columns)

# 2. Transformations: still lazy
daily = (
    lines
    .filter(F.col("QTY") > 0)
    .with_column("SALE_DATE", F.to_date("SOLD_AT"))
    .with_column("NET", F.col("QTY") * F.col("UNIT_PRICE") - F.col("DISCOUNT"))
    .group_by("SALE_DATE", "STORE_ID")
    .agg(F.sum("NET").alias("NET_SALES"), F.count_distinct("TRANSACTION_ID").alias("BASKETS"))
)

# 3. See the SQL Snowpark generated (this is what the warehouse will run)
print(daily.queries["queries"][-1][:500], "...\n")

# 4. Window function: rank stores per day
w = Window.partition_by("SALE_DATE").order_by(F.col("NET_SALES").desc())
ranked = daily.with_column("RANK_IN_DAY", F.rank().over(w))

# 5. ACTION: pull a small result to the client
ranked.filter(F.col("RANK_IN_DAY") <= 3).sort(F.col("SALE_DATE").desc(), "RANK_IN_DAY").show(9)

# 6. ACTION: write the result as a table — computed entirely in Snowflake
ranked.write.save_as_table("RETAIL_LAB.SNOWPARK.STORE_DAILY_SALES", mode="overwrite")
print("rows written:", session.table("RETAIL_LAB.SNOWPARK.STORE_DAILY_SALES").count())

# 7. Small results to pandas are fine (e.g. for a chart)
pdf = session.table("RETAIL_LAB.SNOWPARK.STORE_DAILY_SALES").filter(F.col("STORE_ID") == "S001").to_pandas()
print(pdf.sort_values("SALE_DATE").tail())

# 8. Semi-structured data works too
customers = session.table("RETAIL_RAW.CRM.CUSTOMERS")
tiers = (
    customers
    .select(F.col("V")["loyalty_tier"].cast("string").alias("TIER"))
    .group_by("TIER").count()
)
tiers.show()

session.close()
