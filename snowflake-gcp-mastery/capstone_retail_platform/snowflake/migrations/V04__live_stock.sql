/* Live stock dynamic tables (deploy-only version of stage_05 lesson 04, without the SUSPEND at the end).
   Requires RETAIL_STAGING.REALTIME.SALES_LINES_CLEAN (stage_05 lesson 02). */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_MARTS.OPS;

CREATE OR REPLACE DYNAMIC TABLE RETAIL_STAGING.REALTIME.INVENTORY_LATEST
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = TRANSFORM_WH
  REFRESH_MODE = AUTO
AS
SELECT snapshot_date, store_id, sku, opening_qty
FROM RETAIL_RAW.ERP.INVENTORY
QUALIFY ROW_NUMBER() OVER (PARTITION BY store_id, sku ORDER BY snapshot_date DESC, _loaded_at DESC) = 1;

CREATE OR REPLACE DYNAMIC TABLE RETAIL_MARTS.OPS.STORE_STOCK_LIVE
  TARGET_LAG = '5 minutes'
  WAREHOUSE = TRANSFORM_WH
  REFRESH_MODE = AUTO
  COMMENT = 'Live stock per store × sku for flash sales. Lag ≤ 5 min.'
AS
SELECT
  i.store_id,
  i.sku,
  i.snapshot_date                         AS stock_date,
  i.opening_qty,
  COALESCE(SUM(s.qty), 0)                 AS units_sold_since_open,
  i.opening_qty - COALESCE(SUM(s.qty), 0) AS on_hand,
  MAX(s.sold_at)                          AS last_sale_at
FROM RETAIL_STAGING.REALTIME.INVENTORY_LATEST i
LEFT JOIN RETAIL_STAGING.REALTIME.SALES_LINES_CLEAN s
  ON s.store_id = i.store_id
 AND s.sku = i.sku
 AND s.sold_at >= i.snapshot_date::TIMESTAMP_NTZ
GROUP BY i.store_id, i.sku, i.snapshot_date, i.opening_qty;

CREATE SCHEMA IF NOT EXISTS RETAIL_MARTS.APPS COMMENT = 'Streamlit apps';
