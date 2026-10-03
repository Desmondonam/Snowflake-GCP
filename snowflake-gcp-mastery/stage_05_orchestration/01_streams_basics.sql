/* =============================================================================
   Stage 5 · Lesson 01 — Streams: change data capture inside Snowflake
   -----------------------------------------------------------------------------
   A STREAM is a bookmark (offset) on a table. Selecting from it returns the rows
   that changed since the bookmark, with metadata columns:
     METADATA$ACTION    INSERT | DELETE
     METADATA$ISUPDATE  TRUE when the INSERT/DELETE pair represents an UPDATE
     METADATA$ROW_ID    stable row id
   The bookmark moves forward only when the stream is used in a DML statement
   (INSERT/MERGE/…) that COMMITS. A plain SELECT never consumes it.

   HOW TO RUN: worksheet, statement by statement. Role RETAIL_ENGINEER.
   ============================================================================= */
USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE LAB_WH;
CREATE SCHEMA IF NOT EXISTS RETAIL_LAB.STREAMS_DEMO;
USE SCHEMA RETAIL_LAB.STREAMS_DEMO;

CREATE OR REPLACE TABLE STOCK (store_id STRING, sku STRING, qty INT);
INSERT INTO STOCK VALUES ('S001','SKU-00001',10), ('S001','SKU-00002',5), ('S013','SKU-00001',8);

-- 1. Standard stream: inserts, updates and deletes
CREATE OR REPLACE STREAM STOCK_STRM ON TABLE STOCK;
SELECT * FROM STOCK_STRM;                         -- empty: the bookmark starts NOW

INSERT INTO STOCK VALUES ('S002','SKU-00003',7);
UPDATE STOCK SET qty = 9 WHERE store_id = 'S001' AND sku = 'SKU-00001';
DELETE FROM STOCK WHERE store_id = 'S013';

SELECT *, METADATA$ACTION, METADATA$ISUPDATE FROM STOCK_STRM;
-- S002 insert; S001/SKU-00001 appears as DELETE(10)+INSERT(9) with ISUPDATE = TRUE; S013 delete.
-- Note: the stream shows the NET change since the offset (insert-then-delete of a row shows nothing).

SELECT SYSTEM$STREAM_HAS_DATA('RETAIL_LAB.STREAMS_DEMO.STOCK_STRM');   -- TRUE

-- 2. Consume: DML that reads the stream advances the offset when it commits
CREATE OR REPLACE TABLE STOCK_CHANGES_LOG (store_id STRING, sku STRING, qty INT, action STRING, is_update BOOLEAN, logged_at TIMESTAMP_LTZ);
INSERT INTO STOCK_CHANGES_LOG
SELECT store_id, sku, qty, METADATA$ACTION, METADATA$ISUPDATE, CURRENT_TIMESTAMP() FROM STOCK_STRM;
SELECT * FROM STOCK_STRM;                         -- empty again
SELECT * FROM STOCK_CHANGES_LOG;

-- 3. A rolled-back transaction does NOT advance the offset
INSERT INTO STOCK VALUES ('S003','SKU-00004',1);
BEGIN;
INSERT INTO STOCK_CHANGES_LOG SELECT store_id, sku, qty, METADATA$ACTION, METADATA$ISUPDATE, CURRENT_TIMESTAMP() FROM STOCK_STRM;
ROLLBACK;
SELECT * FROM STOCK_STRM;                         -- S003 is still there

-- 4. Two consumers = two streams. One stream consumed by two tasks means the
--    first task to commit "wins" and the second sees nothing.
CREATE OR REPLACE STREAM STOCK_STRM_FOR_AUDIT ON TABLE STOCK;

-- 5. Append-only stream: tracks inserts only; cheaper; perfect for append-only RAW tables
CREATE OR REPLACE STREAM STOCK_APPEND_STRM ON TABLE STOCK APPEND_ONLY = TRUE;
UPDATE STOCK SET qty = 0;                          -- not visible in an append-only stream
INSERT INTO STOCK VALUES ('S004','SKU-00005',3);
SELECT *, METADATA$ACTION FROM STOCK_APPEND_STRM;  -- only S004

-- 6. Initial rows: a new stream normally starts empty. SHOW_INITIAL_ROWS returns
--    the table's existing rows on first consumption (handy for initial loads).
CREATE OR REPLACE STREAM STOCK_FULL_STRM ON TABLE STOCK SHOW_INITIAL_ROWS = TRUE;
SELECT COUNT(*) FROM STOCK_FULL_STRM;              -- all current rows

-- 7. Staleness: if a stream isn't consumed within the table's data retention
--    (extended up to 14 days by MAX_DATA_EXTENSION_TIME_IN_DAYS) it becomes STALE and must be recreated.
SHOW STREAMS IN SCHEMA RETAIL_LAB.STREAMS_DEMO;    -- see stale, stale_after, mode
