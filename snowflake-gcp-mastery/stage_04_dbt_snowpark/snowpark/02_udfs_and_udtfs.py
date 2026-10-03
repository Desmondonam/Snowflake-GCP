"""Snowpark lesson 02 — UDFs, vectorised UDFs and UDTFs (Python code running inside Snowflake).

  UDF            scalar: one row in, one value out           e.g. normalise a phone number
  Vectorised UDF a pandas Series batch in, a Series out      faster for numeric/ML work
  UDTF           one row (or a partition) in, MANY rows out  e.g. explode a basket into product pairs

Permanent functions are stored in a stage and callable from plain SQL by anyone with USAGE.
Third-party packages come from Snowflake's Anaconda channel (session.add_packages).

Run:  cd stage_04_dbt_snowpark/snowpark ; python 02_udfs_and_udtfs.py
"""
import re
from itertools import combinations

import pandas as pd
import snowflake.snowpark.functions as F
from snowflake.snowpark.types import FloatType, IntegerType, PandasSeriesType, StringType, StructField, StructType

from _session import get_session

session = get_session()
session.sql("create stage if not exists RETAIL_LAB.SNOWPARK.UDF_STAGE").collect()
session.add_packages("pandas")


# --- 1. Scalar UDF -------------------------------------------------------------------------
def normalise_phone(phone: str) -> str:
    """+254 7xx… / +974 … → digits only with country code; None stays None."""
    if phone is None:
        return None
    digits = re.sub(r"\D", "", phone)
    return "+" + digits if digits else None


session.udf.register(
    normalise_phone, name="RETAIL_LAB.SNOWPARK.NORMALISE_PHONE",
    return_type=StringType(), input_types=[StringType()],
    is_permanent=True, stage_location="@RETAIL_LAB.SNOWPARK.UDF_STAGE", replace=True,
)
session.sql("""
    select v:phone::string as raw_phone, RETAIL_LAB.SNOWPARK.NORMALISE_PHONE(v:phone::string) as clean
    from RETAIL_RAW.CRM.CUSTOMERS limit 5
""").show()


# --- 2. Vectorised (pandas) UDF -------------------------------------------------------------
def margin_pct(net: pd.Series, cost: pd.Series) -> pd.Series:
    return ((net - cost) / net.where(net != 0)).round(4)


session.udf.register(
    margin_pct, name="RETAIL_LAB.SNOWPARK.MARGIN_PCT",
    return_type=PandasSeriesType(FloatType()),
    input_types=[PandasSeriesType(FloatType()), PandasSeriesType(FloatType())],
    is_permanent=True, stage_location="@RETAIL_LAB.SNOWPARK.UDF_STAGE", replace=True,
    max_batch_size=10_000,
)
session.sql("select RETAIL_LAB.SNOWPARK.MARGIN_PCT(100::float, 72::float) as m").show()


# --- 3. UDTF: basket → product pairs (market-basket analysis input) -------------------------
class BasketPairs:
    """Called once per row of a partition (one transaction); emits all SKU pairs at the end."""

    def __init__(self):
        self.skus = []

    def process(self, sku: str):
        self.skus.append(sku)
        return None  # nothing emitted per row

    def end_partition(self):
        for a, b in combinations(sorted(set(self.skus)), 2):
            yield (a, b)


session.udtf.register(
    BasketPairs, name="RETAIL_LAB.SNOWPARK.BASKET_PAIRS",
    output_schema=StructType([StructField("SKU_A", StringType()), StructField("SKU_B", StringType())]),
    input_types=[StringType()],
    is_permanent=True, stage_location="@RETAIL_LAB.SNOWPARK.UDF_STAGE", replace=True,
)

# Top product pairs bought together (the UDTF partitions by transaction)
session.sql("""
    select p.sku_a, p.sku_b, count(*) as baskets
    from (select transaction_id, sku from RETAIL_RAW.POS.SALES_LINES where qty > 0
          and sold_at >= dateadd(day, -14, (select max(sold_at) from RETAIL_RAW.POS.SALES_LINES))) s,
         table(RETAIL_LAB.SNOWPARK.BASKET_PAIRS(s.sku) over (partition by s.transaction_id)) p
    group by 1, 2 order by baskets desc limit 10
""").show()

session.sql("show user functions in schema RETAIL_LAB.SNOWPARK").show()
session.close()
