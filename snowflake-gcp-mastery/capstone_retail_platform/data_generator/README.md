# RetailOne data generator

Deterministic fake data for the whole course. Same seed → same files, so your numbers are reproducible,
and `new-day` keeps evolving the same world (customers change tier, prices move, new sign-ups appear).

## What it produces

| Source folder | Format | Grain / content | Lands in |
| --- | --- | --- | --- |
| `pos_sales/dt=…/store_<id>.csv` | CSV | one row per POS line item (returns = negative qty) | `RETAIL_RAW.POS.SALES_LINES` |
| `pos_control/dt=…/control_totals.csv` | CSV | POS "Z-report": totals per store per day | `RETAIL_RAW.POS.CONTROL_TOTALS` |
| `ecom_orders/dt=…/orders.parquet` | Parquet | one row per online order line; **`delivery_method` column appears after day 60** | `RETAIL_RAW.ECOM.ORDERS` |
| `crm_customers/dt=…/customers.json` | NDJSON | day 1: all 5,000 customers; later: only changed/new (CDC-like) | `RETAIL_RAW.CRM.CUSTOMERS` |
| `erp_products/dt=…/products.csv` | CSV | day 1: 500 SKUs; later: price changes | `RETAIL_RAW.ERP.PRODUCTS` |
| `erp_stores/dt=…/stores.csv` | CSV | 20 stores (12 KE, 8 QA), day 1 only | `RETAIL_RAW.ERP.STORES` |
| `erp_inventory/dt=…/inventory.csv` | CSV | opening stock per store × SKU × day (10,000 rows/day) | `RETAIL_RAW.ERP.INVENTORY` |
| `ads/dt=…/ads_<platform>_<run>.json` | NDJSON | campaign × ad × day spend/impressions/clicks | `RETAIL_RAW.ADS.AD_PERFORMANCE` |
| `web_events/dt=…/events.json` | NDJSON | ad clicks, email opens, page views, purchases | `RETAIL_RAW.WEB.EVENTS` |
| `reviews/dt=…/reviews.json` | NDJSON | product reviews with rating and text | `RETAIL_RAW.ECOM.REVIEWS` |

Volume: about 6,000 POS lines, 700 online order lines and 3,000 web events per day. 90 days ≈ 160 MB, ~2,700 files.

### Identity keys (why customer 360 is possible)

- POS lines carry `loyalty_id` (only for loyalty members; others are anonymous).
- Online orders and web events carry `customer_email` (80% are CRM customers, 20% guest checkouts).
- CRM holds `customer_id`, `loyalty_id` and `email`, so it is the bridge: Stage 4 builds `int_customer_identity`.

## Commands (repo root, venv active, `.env` loaded)

```powershell
# 90 days of history ending yesterday, written locally only (inspect before uploading)
python capstone_retail_platform/data_generator/generate.py backfill --days 90

# same, and upload to gs://$env:GCS_LANDING_BUCKET (create the Snowpipes FIRST, see Stage 2)
python capstone_retail_platform/data_generator/generate.py backfill --days 90 --upload

# the next day, as if the stores had just closed
python capstone_retail_platform/data_generator/generate.py new-day --upload

# what has been generated so far?
python capstone_retail_platform/data_generator/generate.py status
```

### Chaos options (real pipelines must survive these)

| Option | What happens | What should catch it |
| --- | --- | --- |
| `--inject-bad-file` | Adds `pos_sales/dt=…/store_S999_corrupt.csv` with text in numeric/date columns | `ON_ERROR = SKIP_FILE`, `COPY_HISTORY` shows `LOAD_FAILED` |
| `--duplicate-file` | Re-sends store S001's file as `store_S001_resend.csv` | Staging dedupe on `(transaction_id, line_no)`; reconciliation still passes |
| `--late-store S007` | Holds back S007's file; it arrives with the **next** run | Airflow arrival check fails/waits; reconciliation fails for that day until it lands |
| (automatic) schema change | `ecom_orders` gains `delivery_method` after day 60 | `ENABLE_SCHEMA_EVOLUTION` on the RAW table |

```powershell
python capstone_retail_platform/data_generator/generate.py new-day --upload --inject-bad-file --duplicate-file --late-store S007
```

### Acceptance test 3: an SCD2 change you control

```powershell
python capstone_retail_platform/data_generator/generate.py change-tier --customer-id C00042 --tier PLATINUM
python capstone_retail_platform/data_generator/generate.py new-day --upload
```

After the next pipeline run, `dim_customer` has a new current row for C00042 and older sales still join to the old tier.

## Re-running and idempotency

- Output is deterministic per date. Re-running `backfill` rewrites the same files (ads files get a new run id).
- Upload overwrites objects with the same name; GCS emits new events, and RAW may receive the rows again.
  That is fine **by design**: RAW is append-only and staging de-duplicates. This is exactly what happens with real sources.
- Delete `output/` (and the `_state.json` inside it) to start a brand-new world.

## Reading the code

[generate.py](generate.py) is organised as: configuration → `RetailWorld` (master data that evolves per day + fact generators)
→ `Writer` (CSV/NDJSON/Parquet) → `generate_day` (one landing day) → state/upload/CLI. Read `RetailWorld.advance`
to see how customer and product changes are simulated: that is what feeds SCD Type 2 later.
