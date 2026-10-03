-- Fails the build when any store-day disagrees with the POS Z-report by more than the tolerance
-- (var reconciliation_tolerance, default 0.5%) or is missing entirely.
-- Returned rows = the failing store-days, so `dbt test` output tells you exactly where to look.
{{ config(severity='error', tags=['reconciliation']) }}

select business_date, store_id, status, pos_net_amount, wh_net_amount, diff_pct
from {{ ref('rpt_pos_reconciliation') }}
where status <> 'OK'
