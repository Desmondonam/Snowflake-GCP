# Data contracts for RetailOne

A **data contract** is an agreement between a data producer (e.g. the POS team) and the data platform about the
**shape, meaning, quality and timeliness** of a feed — written down, versioned, and enforced by tests.
It protects against the silent failure modes: a renamed column, a unit change (cents → units), a new status value,
a feed that quietly stops.

## Example: POS sales lines (producer: Store Systems team)

```yaml
contract: pos_sales_lines
version: 1.2.0
owner: store-systems@retailone.example        # producer
consumer: data-platform@retailone.example
delivery:
  location: gs://<landing>/pos_sales/dt=YYYY-MM-DD/store_<store_id>.csv
  format: csv, UTF-8, header row, comma, double-quote enclosure
  schedule: one file per store per business day by 02:00 store local time
  completeness: one control_totals.csv per business day listing every store that traded
schema:                                        # columns are positional: ORDER IS PART OF THE CONTRACT
  - {name: transaction_id, type: string, required: true, pattern: "^[TR]-S\\d{3}-\\d{8}-\\d{5}$"}
  - {name: line_no,        type: integer, required: true, min: 1}
  - {name: store_id,       type: string,  required: true, references: erp_stores.store_id}
  - {name: sku,            type: string,  required: true, references: erp_products.sku}
  - {name: qty,            type: decimal(10,2), required: true, note: "negative for returns"}
  - {name: unit_price,     type: decimal(12,2), required: true, unit: USD, min: 0}
  - {name: discount,       type: decimal(12,2), required: true, unit: USD}
  - {name: loyalty_id,     type: string,  required: false}
  - {name: sold_at,        type: timestamp, required: true, timezone: store local}
  - {name: promo_code,     type: string,  required: false, allowed: [PROMO10, WEEKEND15, LOYAL20, FLASH25]}
  - {name: tender_type,    type: string,  required: true, allowed: [CASH, CARD, MPESA, WALLET]}
quality:
  - unique: [transaction_id, line_no]
  - reconciliation: sum(qty*unit_price - discount) per store-day equals control_totals.net_amount within 0.5%
sla:
  freshness: data for business day D available in RAW by 03:00 on D+1
  support: producer on-call responds within 4 business hours to a breach
change_management:
  additive changes (new column at the END): 2 weeks notice, minor version bump
  breaking changes (rename, reorder, type/unit change, removal): 6 weeks notice, major version bump, parallel feed during migration
```

## Where each clause is enforced in this repo

| Clause | Enforcement |
| --- | --- |
| Format / types | RAW typed table + `ON_ERROR = SKIP_FILE` (bad file rejected, visible in `COPY_HISTORY`) |
| Required / unique / allowed values | staging tests in `_pos__models.yml` (`not_null`, `unique_combination_of_columns`, `accepted_values`) |
| References | `relationships` tests (warn on facts) |
| Completeness + reconciliation | `pos_control` feed → `rpt_pos_reconciliation` + blocking singular test |
| Freshness / SLA | `dbt source freshness` (`_pos__sources.yml`) + Airflow arrival sensor |
| Consumer-facing schema | `contract: {enforced: true}` on `fct_sales_line` and `dim_customer` (BI can rely on names/types) |
| Change management | the YAML above lives in Git; producers raise a PR to change it |

## What a contract protects against (interview answer)

Silent breakage. Without a contract, a producer renames `unit_price` or switches to cents, loads succeed, and dashboards are
wrong for weeks. With one, the change is negotiated in advance, versioned, and if it slips through anyway, a test fails at the
boundary (staging) — before bad numbers reach marts and people.
