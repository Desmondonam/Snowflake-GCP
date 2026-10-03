/* =============================================================================
   Stage 3 · Step 06 (optional) — Data Vault 2.0 in miniature
   -----------------------------------------------------------------------------
   Data Vault separates:
     HUBS       unique business keys            (customer_id, sku)
     LINKS      relationships between hubs      (a sale links customer + product)
     SATELLITES descriptive attributes + history (customer profile over time)
   Everything is INSERT-ONLY with load_dts and record_source → fully auditable,
   and new sources plug in without remodelling. Marts (stars) are then built on top.

   When to choose it over Kimball-only: many volatile sources feeding the same
   entities, strict audit needs, or frequent source changes. Cost: more tables
   and joins; you still need star schemas for BI.
   HOW TO RUN: snow sql -c retail_engineer -f stage_03_modeling/06_data_vault_sketch.sql
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.VAULT;
USE SCHEMA RETAIL_LAB.VAULT;

CREATE TABLE IF NOT EXISTS HUB_CUSTOMER (
  customer_hk   BINARY(16)  NOT NULL,   -- MD5 of the business key
  customer_id   STRING      NOT NULL,
  load_dts      TIMESTAMP_NTZ NOT NULL,
  record_source STRING      NOT NULL
);
CREATE TABLE IF NOT EXISTS HUB_PRODUCT (
  product_hk BINARY(16) NOT NULL, sku STRING NOT NULL, load_dts TIMESTAMP_NTZ NOT NULL, record_source STRING NOT NULL
);
CREATE TABLE IF NOT EXISTS LINK_SALE_LINE (
  sale_line_hk  BINARY(16) NOT NULL,
  customer_hk   BINARY(16) NOT NULL,
  product_hk    BINARY(16) NOT NULL,
  transaction_id STRING, line_no INT,
  load_dts TIMESTAMP_NTZ NOT NULL, record_source STRING NOT NULL
);
CREATE TABLE IF NOT EXISTS SAT_CUSTOMER_PROFILE (
  customer_hk BINARY(16) NOT NULL,
  load_dts    TIMESTAMP_NTZ NOT NULL,
  hash_diff   BINARY(16) NOT NULL,      -- detects real changes
  segment STRING, loyalty_tier STRING, city STRING, country_code STRING,
  record_source STRING NOT NULL
);

-- Load pattern: insert only what is new. Rerunning is a no-op.
INSERT INTO HUB_CUSTOMER
SELECT DISTINCT MD5_BINARY(s.customer_id), s.customer_id, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 'CRM'
FROM RETAIL_LAB.STG.CRM_CUSTOMER_CHANGES s
WHERE NOT EXISTS (SELECT 1 FROM HUB_CUSTOMER h WHERE h.customer_hk = MD5_BINARY(s.customer_id));

INSERT INTO HUB_PRODUCT
SELECT DISTINCT MD5_BINARY(s.sku), s.sku, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 'ERP'
FROM RETAIL_LAB.STG.ERP_PRODUCT_CHANGES s
WHERE NOT EXISTS (SELECT 1 FROM HUB_PRODUCT h WHERE h.product_hk = MD5_BINARY(s.sku));

INSERT INTO SAT_CUSTOMER_PROFILE
SELECT MD5_BINARY(s.customer_id), s.updated_at,
       MD5_BINARY(CONCAT_WS('|', COALESCE(s.segment, ''), COALESCE(s.loyalty_tier, ''), COALESCE(s.city, ''), COALESCE(s.country_code, ''))),
       s.segment, s.loyalty_tier, s.city, s.country_code, 'CRM'
FROM RETAIL_LAB.STG.CRM_CUSTOMER_CHANGES s
WHERE NOT EXISTS (SELECT 1 FROM SAT_CUSTOMER_PROFILE t
                  WHERE t.customer_hk = MD5_BINARY(s.customer_id) AND t.load_dts = s.updated_at);

INSERT INTO LINK_SALE_LINE
SELECT MD5_BINARY(p.transaction_id || '|' || p.line_no), MD5_BINARY(c.customer_id), MD5_BINARY(p.sku),
       p.transaction_id, p.line_no, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, 'POS'
FROM RETAIL_LAB.STG.POS_SALES_LINES p
JOIN RETAIL_LAB.STG.CRM_CUSTOMERS_LATEST c ON c.loyalty_id = p.loyalty_id
WHERE NOT EXISTS (SELECT 1 FROM LINK_SALE_LINE l WHERE l.sale_line_hk = MD5_BINARY(p.transaction_id || '|' || p.line_no));

-- "Current profile" from the satellite = the latest load per hub key
SELECT h.customer_id, s.segment, s.loyalty_tier, s.load_dts
FROM HUB_CUSTOMER h
JOIN SAT_CUSTOMER_PROFILE s ON s.customer_hk = h.customer_hk
QUALIFY ROW_NUMBER() OVER (PARTITION BY h.customer_hk ORDER BY s.load_dts DESC) = 1
LIMIT 10;
