# Capstone 6 — "Make it fast and cheap": results

Dataset: `RETAIL_LAB.PERF.FCT_SALES_LINE_BIG`, ___ M rows, ___ GB, ___ micro-partitions.
Paste the output of the RESULTS query in [04_optimizations.sql](04_optimizations.sql) below, then write the story.

| Query | Variant | Size | Elapsed (s) | % partitions scanned | MB scanned | Spilled MB | Est. credits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Q1 weekly store sales | baseline | XS | | | | | |
| Q1 weekly store sales | clustered | XS | | | | | |
| Q2 month by region | baseline (function filter) | XS | | | | | |
| Q2 month by region | clustered, function filter | XS | | | | | |
| Q2 month by region | clustered, range filter | XS | | | | | |
| Q3 black friday by category | baseline | XS | | | | | |
| Q3 black friday by category | clustered | XS | | | | | |
| Q4 point lookup loyalty_id | baseline | XS | | | | | |
| Q4 point lookup loyalty_id | search optimization | XS | | | | | |
| Q5 distinct customers | baseline XS | XS | | | | | |
| Q5 distinct customers | clustered S | S | | | | | |
| Q5 distinct customers | clustered M | M | | | | | |
| Q5 distinct customers | approx M | M | | | | | |
| Q6 daily region dashboard | baseline | XS | | | | | |
| Q6 daily region dashboard | clustered | XS | | | | | |
| Q6 daily region dashboard | materialized view | XS | | | | | |

## The story (practise saying this in 60 seconds)

> "The weekly-sales dashboard took __ s and scanned __% of partitions even though it only asked for four weeks, because the
> fact had been loaded out of date order. I clustered it on (sale_date, store_id): the same query scanned __% and ran in __ s.
> A filter written as TO_CHAR(sale_date) was rewritten as a date range so pruning could work. The distinct-customer query was
> spilling __ MB on XS; on Small it stopped spilling and cost about the same credits because it ran __x faster. The executive
> dashboard now reads a __-row materialized view instead of __M rows, and the customer-service lookup uses search optimization:
> __ s → __ s. I also measured the background cost of each feature before recommending it."

## What I would NOT do, and why

- Cluster small tables (< ~1 TB or a few thousand partitions): natural load order is usually enough; clustering costs credits.
- Cluster on a high-cardinality key like `sales_line_id` or `customer_id` (unless point lookups dominate — that's what search optimization is for).
- Size up a warehouse for a query that isn't spilling or CPU-bound (more cost, same time).
