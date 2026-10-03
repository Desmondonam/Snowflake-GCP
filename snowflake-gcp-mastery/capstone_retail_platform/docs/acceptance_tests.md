# Acceptance tests — do these before you call RetailOne done

Record the date, the result and a screenshot for each.

## 1. A new day lands with no manual step (≤ 10 minutes)

```powershell
python capstone_retail_platform/data_generator/generate.py new-day --upload     # note the date it prints
```

Wait up to 10 minutes, then:

```sql
SELECT COUNT(DISTINCT store_id) AS stores, COUNT(*) AS lines, MAX(_loaded_at) AS last_load
FROM RETAIL_RAW.POS.SALES_LINES WHERE sold_at::DATE = '<that date>';           -- 20 stores
SELECT COUNT(*) FROM RETAIL_RAW.POS.CONTROL_TOTALS WHERE business_date = '<that date>';   -- 20
SELECT COUNT(*) FROM RETAIL_STAGING.REALTIME.SALES_LINES_CLEAN WHERE sold_at::DATE = '<that date>';  -- task merged them
```

- [ ] Passed on: ______

## 2. The DAG is green; all tests pass; reconciliation within 0.5%

Trigger `retail_daily` with `{"business_date": "<that date>"}` (Airflow UI).

```sql
SELECT status, COUNT(*) FROM RETAIL_MARTS.OPS.RPT_POS_RECONCILIATION
WHERE business_date = '<that date>' GROUP BY 1;        -- only OK, 20 rows
```

- [ ] Grid view all green, Slack/log summary posted. Passed on: ______

## 3. SCD2: a tier change creates a new version; old sales keep the old tier

```powershell
python capstone_retail_platform/data_generator/generate.py change-tier --customer-id C00042 --tier PLATINUM
python capstone_retail_platform/data_generator/generate.py new-day --upload
```

Wait for Snowpipe, run the DAG (or `dbt build --target prod`), then:

```sql
SELECT customer_id, loyalty_tier, valid_from, valid_to, is_current
FROM RETAIL_MARTS.CORE.DIM_CUSTOMER WHERE customer_id = 'C00042' ORDER BY valid_from;   -- new current PLATINUM row

SELECT c.loyalty_tier, MIN(f.sale_date), MAX(f.sale_date), COUNT(*)
FROM RETAIL_MARTS.SALES.FCT_SALES_LINE f
JOIN RETAIL_MARTS.CORE.DIM_CUSTOMER c ON c.customer_sk = f.customer_sk
WHERE f.customer_id = 'C00042' GROUP BY 1;     -- older sales still on the old tier
```

- [ ] Passed on: ______

## 4. `FR_ANALYST`: emails masked, only one region visible

Run [stage_07_quality_governance/07_test_as_each_role.sql](../../stage_07_quality_governance/07_test_as_each_role.sql) (with `USE SECONDARY ROLES NONE`).

- [ ] Emails `*****@example.com`, only `KE` in `fct_sales_line`. Passed on: ______

## 5. `terraform destroy` and `apply` rebuild the platform

Follow [terraform/README.md](../terraform/README.md#acceptance-test-5--destroy-and-rebuild) and the `next_steps` output.
Then repeat tests 1, 2 and 4.

- [ ] Rebuilt from scratch in ____ minutes. Passed on: ______

## 6. Explain it in 4 minutes, then answer "what would you change at 100× the volume?"

Use [docs/architecture.md](architecture.md) and [interview/seven_beats_script.md](../../interview/seven_beats_script.md).
Record yourself.

- [ ] Recording ≤ 4:00. Link/file: ______
