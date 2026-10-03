/* =============================================================================
   Stage 3 · Step 04 — Fact tables
   -----------------------------------------------------------------------------
   FCT_SALES_LINE       transaction fact   grain: one row per POS or online order LINE
   FCT_INVENTORY_DAILY  periodic snapshot  grain: store × product × day
   FCT_AD_PERFORMANCE   transaction-ish    grain: ad × day

   Kimball's four steps, applied to sales:
     1 process   = selling (store + online)
     2 grain     = one line item  ← decide FIRST; everything else follows
     3 dimensions= date, store, product (version at sale time), customer (version at sale time), promotion, channel
     4 facts     = quantity, gross, discount, net, cost, margin  (all additive; returns are negative lines)
   transaction_id stays on the fact as a DEGENERATE dimension (no dim table of its own).

   HOW TO RUN: snow sql -c retail_engineer -f stage_03_modeling/04_facts.sql
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA RETAIL_LAB.STAR;

/* ---------------------------------------------------------------------------
   FCT_SALES_LINE
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE FCT_SALES_LINE AS
WITH pos AS (
  SELECT 'STORE' AS channel, transaction_id, line_no, store_id, sku, qty, unit_price, discount,
         promo_code, sold_at, loyalty_id, NULL::STRING AS customer_email, NULL::STRING AS ship_country, _loaded_at
  FROM RETAIL_LAB.STG.POS_SALES_LINES
),
online AS (
  SELECT 'ONLINE', order_id, order_line, 'ONLINE', sku, qty, unit_price, discount,
         NULL, ordered_at, NULL, customer_email, ship_country, _loaded_at
  FROM RETAIL_LAB.STG.ECOM_ORDER_LINES
  WHERE order_status <> 'CANCELLED'          -- cancelled orders are not sales
),
lines AS (SELECT * FROM pos UNION ALL SELECT * FROM online),
crm AS (SELECT customer_id, loyalty_id, email FROM RETAIL_LAB.STG.CRM_CUSTOMERS_LATEST),
resolved AS (
  -- identity: store sales via loyalty card, online sales via email
  SELECT l.*, COALESCE(by_card.customer_id, by_email.customer_id) AS customer_id
  FROM lines l
  LEFT JOIN crm by_card  ON l.channel = 'STORE'  AND by_card.loyalty_id = l.loyalty_id
  LEFT JOIN crm by_email ON l.channel = 'ONLINE' AND by_email.email     = l.customer_email
)
SELECT
  MD5(r.channel || '|' || r.transaction_id || '|' || r.line_no)  AS sales_line_key,
  r.channel,
  r.transaction_id,                                               -- degenerate dimension
  r.line_no,
  TO_NUMBER(TO_CHAR(r.sold_at, 'YYYYMMDD'))                       AS date_key,
  r.sold_at::DATE                                                 AS sale_date,
  r.sold_at,
  s.store_sk,
  r.store_id,
  COALESCE(s.region, r.ship_country)                              AS store_region,
  COALESCE(p.product_sk, '-1')                                    AS product_sk,
  r.sku,                                                          -- natural key kept for debugging/joins
  COALESCE(c.customer_sk, '-1')                                   AS customer_sk,
  COALESCE(pr.promotion_sk, MD5('NONE'))                          AS promotion_sk,
  r.qty::NUMBER(10,2)                                             AS quantity,
  r.unit_price,
  (r.qty * r.unit_price)::NUMBER(14,2)                            AS gross_amount,
  r.discount::NUMBER(14,2)                                        AS discount_amount,
  (r.qty * r.unit_price - r.discount)::NUMBER(14,2)               AS net_amount,
  (r.qty * COALESCE(p.unit_cost, 0))::NUMBER(14,2)                AS cost_amount,
  (r.qty * r.unit_price - r.discount - r.qty * COALESCE(p.unit_cost, 0))::NUMBER(14,2) AS margin_amount,
  r.qty < 0                                                       AS is_return,
  r._loaded_at
FROM resolved r
LEFT JOIN DIM_STORE s     ON s.store_id = r.store_id
LEFT JOIN DIM_PRODUCT p   ON p.sku = r.sku
                         AND r.sold_at >= p.valid_from AND r.sold_at < p.valid_to   -- price/cost AT sale time
LEFT JOIN DIM_CUSTOMER c  ON c.customer_id = r.customer_id
                         AND r.sold_at >= c.valid_from AND r.sold_at < c.valid_to   -- tier/segment AT sale time
LEFT JOIN DIM_PROMOTION pr ON pr.promo_code = r.promo_code;

/* ---------------------------------------------------------------------------
   FCT_INVENTORY_DAILY — periodic snapshot. Quantities on hand are SEMI-ADDITIVE:
   you may SUM across stores or products, but NOT across days (use the last day or an average).
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE FCT_INVENTORY_DAILY AS
WITH sold AS (
  SELECT store_id, sku, sale_date, SUM(quantity) AS units_sold
  FROM FCT_SALES_LINE
  WHERE channel = 'STORE'
  GROUP BY 1, 2, 3
)
SELECT
  MD5(i.snapshot_date::STRING || '|' || i.store_id || '|' || i.sku) AS inventory_key,
  TO_NUMBER(TO_CHAR(i.snapshot_date, 'YYYYMMDD'))                    AS date_key,
  i.snapshot_date,
  s.store_sk, i.store_id, s.region AS store_region,
  COALESCE(p.product_sk, '-1') AS product_sk, i.sku,
  i.opening_qty,
  COALESCE(sold.units_sold, 0)::NUMBER(12,2) AS units_sold,
  (i.opening_qty - COALESCE(sold.units_sold, 0))::NUMBER(12,2) AS closing_qty
FROM RETAIL_LAB.STG.ERP_INVENTORY i
LEFT JOIN sold ON sold.store_id = i.store_id AND sold.sku = i.sku AND sold.sale_date = i.snapshot_date
LEFT JOIN DIM_STORE s   ON s.store_id = i.store_id
LEFT JOIN DIM_PRODUCT p ON p.sku = i.sku
                       AND i.snapshot_date::TIMESTAMP_NTZ >= p.valid_from AND i.snapshot_date::TIMESTAMP_NTZ < p.valid_to;

/* ---------------------------------------------------------------------------
   FCT_AD_PERFORMANCE — grain: ad × day. Store the PARTS (spend, impressions, clicks);
   compute ratios (CTR, CPC, ROAS) at query time. Ratios are non-additive.
   --------------------------------------------------------------------------- */
CREATE OR REPLACE TABLE FCT_AD_PERFORMANCE AS
SELECT MD5(a.ad_date::STRING || '|' || a.ad_id)   AS ad_performance_key,
       TO_NUMBER(TO_CHAR(a.ad_date, 'YYYYMMDD'))  AS date_key,
       a.ad_date,
       c.campaign_sk, a.campaign_id, a.ad_id, a.platform,
       ch.channel_sk,
       a.spend, a.impressions, a.clicks, a.conversions
FROM RETAIL_LAB.STG.ADS_AD_PERFORMANCE a
LEFT JOIN DIM_CAMPAIGN c ON c.campaign_id = a.campaign_id
LEFT JOIN DIM_CHANNEL ch ON ch.channel_code = c.channel_code;

/* ---------------------------------------------------------------------------
   Use the star: a few business questions
   --------------------------------------------------------------------------- */
-- Daily net sales and margin % by country (margin % = SUM(margin)/SUM(net), never AVG of ratios)
SELECT f.sale_date, f.store_region,
       SUM(f.net_amount) AS net_sales,
       ROUND(100 * SUM(f.margin_amount) / NULLIF(SUM(f.net_amount), 0), 1) AS margin_pct
FROM FCT_SALES_LINE f
GROUP BY 1, 2 ORDER BY 1 DESC, 2 LIMIT 20;

-- Sales by loyalty tier AS IT WAS at the time of sale (the point of SCD2)
SELECT c.loyalty_tier, COUNT(DISTINCT f.transaction_id) AS baskets, SUM(f.net_amount) AS net_sales
FROM FCT_SALES_LINE f JOIN DIM_CUSTOMER c ON c.customer_sk = f.customer_sk
GROUP BY 1 ORDER BY 3 DESC;

-- Weekend effect in Qatar uses the Qatar weekend flag
SELECT d.is_weekend_qa, AVG(daily.net) AS avg_daily_net
FROM (SELECT sale_date, SUM(net_amount) AS net FROM FCT_SALES_LINE WHERE store_region = 'QA' GROUP BY 1) daily
JOIN DIM_DATE d ON d.date_day = daily.sale_date GROUP BY 1;
