"""RetailOne store manager app — Streamlit in Snowflake.

A store manager picks a store and sees: sales & margin trend, today's low-stock items (from the live
dynamic table) and how the store's best sellers are reviewed (Cortex sentiment).

Deploy: see stage_08_advanced/README.md (Snowsight UI or `snow streamlit deploy`).
The app runs inside Snowflake with the OWNER role's privileges — choose that role deliberately.
"""
import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()
session.query_tag = "streamlit_store_manager"

st.set_page_config(page_title="RetailOne · Store manager", layout="wide")
st.title("RetailOne · Store manager")


@st.cache_data(ttl=600)
def load_stores() -> pd.DataFrame:
    return session.sql("""
        select store_id, store_name, city, region
        from RETAIL_MARTS.CORE.DIM_STORE
        where store_type = 'PHYSICAL'
        order by store_id
    """).to_pandas()


@st.cache_data(ttl=300)
def load_sales(store_id: str, days: int) -> pd.DataFrame:
    return session.sql("""
        with bounds as (select max(sale_date) as max_d from RETAIL_MARTS.SALES.FCT_SALES_LINE)
        select f.sale_date,
               sum(f.net_amount)                    as net_sales,
               sum(f.margin_amount)                 as margin,
               count(distinct f.transaction_id)     as baskets
        from RETAIL_MARTS.SALES.FCT_SALES_LINE f, bounds b
        where f.store_id = ?
          and f.sale_date > dateadd(day, -?, b.max_d)
        group by 1
        order by 1
    """, params=[store_id, days]).to_pandas()


@st.cache_data(ttl=60)
def load_low_stock(store_id: str) -> pd.DataFrame:
    return session.sql("""
        select s.sku, p.product_name, s.on_hand, s.units_sold_since_open, s.last_sale_at
        from RETAIL_MARTS.OPS.STORE_STOCK_LIVE s
        left join RETAIL_MARTS.CORE.DIM_PRODUCT p on p.sku = s.sku and p.is_current
        where s.store_id = ? and s.on_hand <= 10
        order by s.on_hand, s.units_sold_since_open desc
        limit 25
    """, params=[store_id]).to_pandas()


@st.cache_data(ttl=600)
def load_review_sentiment(store_id: str, days: int) -> pd.DataFrame:
    return session.sql("""
        with bounds as (select max(sale_date) as max_d from RETAIL_MARTS.SALES.FCT_SALES_LINE),
        top_skus as (
            select f.sku, sum(f.net_amount) as net_sales
            from RETAIL_MARTS.SALES.FCT_SALES_LINE f, bounds b
            where f.store_id = ? and f.sale_date > dateadd(day, -?, b.max_d)
            group by 1 order by 2 desc limit 20
        )
        select t.sku, p.product_name, round(t.net_sales, 2) as net_sales,
               count(r.review_id) as reviews, round(avg(r.sentiment), 2) as avg_sentiment
        from top_skus t
        left join RETAIL_MARTS.CORE.DIM_PRODUCT p on p.sku = t.sku and p.is_current
        left join RETAIL_MARTS.CORE.PRODUCT_REVIEW_SCORES r on r.sku = t.sku
        group by 1, 2, 3
        order by net_sales desc
    """, params=[store_id, days]).to_pandas()


stores = load_stores()
labels = stores["STORE_ID"] + " · " + stores["STORE_NAME"]
col_a, col_b = st.columns([3, 1])
choice = col_a.selectbox("Store", labels)
days = col_b.slider("Days", min_value=7, max_value=90, value=28, step=7)
store_id = choice.split(" · ")[0]

sales = load_sales(store_id, days)
if sales.empty:
    st.warning("No sales for this store in the selected period.")
    st.stop()

k1, k2, k3, k4 = st.columns(4)
net = float(sales["NET_SALES"].sum())
margin = float(sales["MARGIN"].sum())
k1.metric("Net sales", f"{net:,.0f}")
k2.metric("Margin", f"{margin:,.0f}")
k3.metric("Margin %", f"{100 * margin / net:.1f}%" if net else "–")
k4.metric("Baskets", f"{int(sales['BASKETS'].sum()):,}")

st.subheader("Daily net sales and margin")
st.line_chart(sales.set_index("SALE_DATE")[["NET_SALES", "MARGIN"]])

left, right = st.columns(2)
with left:
    st.subheader("Low stock now (≤ 10 units)")
    try:
        st.dataframe(load_low_stock(store_id), use_container_width=True, hide_index=True)
    except Exception:  # noqa: BLE001
        st.info("Live stock table not available — run stage_05_orchestration/04_dynamic_tables.sql.")
with right:
    st.subheader("Best sellers and what customers say")
    try:
        st.dataframe(load_review_sentiment(store_id, days), use_container_width=True, hide_index=True)
    except Exception:  # noqa: BLE001
        st.info("Review sentiment not available — build product_review_scores (Stage 8 lesson 04).")

st.caption("Data: RETAIL_MARTS (dbt), OPS.STORE_STOCK_LIVE (dynamic table, ≤5 min lag), Cortex sentiment.")
