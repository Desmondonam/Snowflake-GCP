# Stage 3 — Data modeling for retail (week 3)

**Goal:** design RetailOne's warehouse the Kimball way (grain first), build the star schema **by hand in SQL**
so you understand every join, and write SCD Type 2 two ways. In Stage 4 dbt automates exactly this — and you
will know what it's doing.

**Prerequisite:** Capstone 2 (RAW loaded with ~90 days).

Everything here builds in `RETAIL_LAB` (a transient sandbox): `RETAIL_LAB.STG` (views) and `RETAIL_LAB.STAR` (tables).
The production versions come from dbt in Stage 4 (`RETAIL_STAGING`, `RETAIL_MARTS`).

| # | File | What you learn |
| --- | --- | --- |
| — | [bus_matrix.md](bus_matrix.md) | The one-page plan: processes × conformed dimensions |
| — | [erd.dbml](erd.dbml) | Paste into dbdiagram.io to draw the ERD |
| 01 | [01_staging_views.sql](01_staging_views.sql) | Typing, renaming, dedupe with `QUALIFY ROW_NUMBER()` |
| 02 | [02_dimensions.sql](02_dimensions.sql) | Date, store (SCD1), product & customer (SCD2 from history), small dims |
| 03 | [03_scd2_incremental_merge.sql](03_scd2_incremental_merge.sql) | The hand-written SCD2 MERGE (interview favourite) |
| 04 | [04_facts.sql](04_facts.sql) | Transaction fact, periodic snapshot, ad fact; point-in-time joins |
| 05 | [05_validate_model.sql](05_validate_model.sql) | Grain, RI, SCD2 integrity, reconciliation, additivity traps |
| 06 | [06_data_vault_sketch.sql](06_data_vault_sketch.sql) | Hubs, links, satellites (optional) |

---

## 1. Concepts in plain language

### 1.1 Kimball's four steps (always in this order)

1. **Choose the business process** — e.g. selling.
2. **Declare the grain** — *what does one row mean?* "One POS or online order **line item**." Grain first, always.
3. **Identify the dimensions** — the who/what/where/when that describe a row: date, store, product, customer, promotion, channel.
4. **Identify the facts** — the numbers measured at that grain: quantity, gross, discount, net, cost, margin.

If you can't say the grain in one sentence, the table will produce wrong numbers.

### 1.2 Three kinds of fact table

| Type | Grain | RetailOne example | Behaviour |
| --- | --- | --- | --- |
| Transaction | one event | `fct_sales_line` | Insert-only, grows with activity |
| Periodic snapshot | entity × period | `fct_inventory_daily` (stock per store per SKU per day) | One row per period even if nothing happened |
| Accumulating snapshot | one process instance | an online order: placed → picked → shipped → delivered | Row is **updated** as milestones happen; several date keys |

### 1.3 Additivity

| Measure | Type | Rule |
| --- | --- | --- |
| Revenue, quantity, spend | Additive | Sum across any dimension |
| Stock on hand, account balance | **Semi-additive** | Sum across stores/products, **not across time** (take last/average) |
| Margin %, CTR, ROAS | **Non-additive** | Store the parts (margin, net; clicks, impressions); compute the ratio at query time |

### 1.4 Dimensions

- **Surrogate key**: a warehouse-owned key (`MD5(natural_key | valid_from)`), stable across rebuilds.
- **Conformed dimension**: one `dim_customer` used by sales, marketing and attribution facts — that's what makes numbers agree across reports.
- **Role-playing**: the same `dim_date` used as order date, ship date, delivery date.
- **Junk dimension**: a few low-cardinality flags bundled together (tender type × is_return × has_promo).
- **Degenerate dimension**: an identifier with no attributes kept on the fact (`transaction_id`).
- **Unknown member**: key `'-1'` so facts never carry NULL foreign keys (anonymous shoppers).

### 1.5 Slowly changing dimensions

| Type | What happens on change | RetailOne use |
| --- | --- | --- |
| 1 | Overwrite | Store name typo, customer email/phone |
| **2** | New row with `valid_from`, `valid_to`, `is_current` | Customer tier/segment/city, product price/category |
| 3 | Keep the previous value in an extra column | "previous_tier" for one-step comparisons |

**Point-in-time join**: a sale joins the customer version valid *at the time of the sale*:

```sql
ON c.customer_id = f.customer_id AND f.sold_at >= c.valid_from AND f.sold_at < c.valid_to
```

Half-open intervals (`>=` and `<`) → no gaps, no double matches.

### 1.6 Alternatives you should be able to discuss

- **Data Vault 2.0** — hubs/links/satellites, insert-only, auditable, absorbs many changing sources; you still build stars on top for BI.
- **One Big Table (OBT)** — one wide denormalised table per use case; fast and simple for a BI tool, but duplicates logic and is hard to change.
- **Medallion** — bronze/silver/gold ≈ RAW/STAGING/MARTS. Same layering idea, different names.

## 2. Step-by-step

```powershell
snow sql -c retail_engineer -f stage_03_modeling/01_staging_views.sql
snow sql -c retail_engineer -f stage_03_modeling/02_dimensions.sql
snow sql -c retail_engineer -f stage_03_modeling/04_facts.sql
```

Then open in a worksheet and run statement by statement:

1. [03_scd2_incremental_merge.sql](03_scd2_incremental_merge.sql) — watch C00042 get a second version.
2. [05_validate_model.sql](05_validate_model.sql) — every check should return zero rows.
3. Optional: [06_data_vault_sketch.sql](06_data_vault_sketch.sql).

Draw the ERD: paste [erd.dbml](erd.dbml) into dbdiagram.io, export `erd.png` into this folder.

## 3. Capstone 3 — "Retail star schema"

Deliverables in this folder:

- [x] Bus matrix ([bus_matrix.md](bus_matrix.md))
- [ ] ERD image (`erd.png`)
- [x] DDL/SQL for `fct_sales_line`, `fct_inventory_daily`, `fct_ad_performance`, `dim_customer` (SCD2), `dim_product` (SCD2), `dim_store`, `dim_date`, `dim_campaign`
- [ ] All checks in `05_validate_model.sql` pass
- [ ] Answer in section 6 below: **what is the grain of each fact, and why?**

## 4. Try this

- Change the customer join in `04_facts.sql` to `BETWEEN valid_from AND valid_to`, rebuild, and count duplicate `sales_line_key`s. Explain why.
- Join sales to `dim_customer` on `is_current = TRUE` instead of the point-in-time join. How does "sales by tier" change? Which answer is right for "how much did Gold members buy last quarter"?
- Generate a late store file (`new-day --upload --late-store S007`), rebuild facts, run the reconciliation check.

## 5. Interview check

<details><summary>What is the grain of a POS fact?</summary>

One row per line item on a receipt (transaction_id + line_no). It is the lowest level the source gives, so every
question (by basket, product, hour, promotion) can be answered by aggregation. Header-level facts lose product detail.
</details>

<details><summary>How do you model returns?</summary>

As negative quantity/amount lines in the same sales fact (with an `is_return` flag and, if available, the original
transaction id). Net sales stays a simple SUM. A separate returns fact only if returns carry their own process attributes.
</details>

<details><summary>Why is inventory semi-additive?</summary>

Stock is a balance at a point in time. Adding Monday's stock to Tuesday's counts the same units twice. You can sum across
stores and products for one day; across time use the closing value of the period or an average.
</details>

<details><summary>When would you choose Data Vault over Kimball?</summary>

Many source systems describing the same entities and changing often, strong audit/regulatory needs, or a large team
loading in parallel. Data Vault is the integration layer; Kimball stars remain the presentation layer on top.
</details>

<details><summary>How do you link an in-store loyalty customer to an online customer?</summary>

Identity resolution: the CRM is the bridge (customer_id ↔ loyalty_id ↔ email). Store sales resolve via loyalty card,
online sales via email; guests get a customer key derived from email so they merge if they later join. Build it as an
identity map (`identifier_type`, `identifier_value` → `customer_id`) and conform it into one `dim_customer`. Probabilistic
matching (name + phone + address) is a later step with confidence scores.
</details>

<details><summary>Write SCD2 by hand.</summary>

See [03_scd2_incremental_merge.sql](03_scd2_incremental_merge.sql): one fixed run timestamp, hash-diff comparison,
close changed current rows, insert new versions for changed + new keys, both in one transaction, idempotent.
</details>

## 6. My answers: grain of each fact and why

- `fct_sales_line`:
- `fct_inventory_daily`:
- `fct_ad_performance`:

## 7. My notes
