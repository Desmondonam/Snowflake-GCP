{#-
  Reconciliation: does the warehouse agree with the POS system's own Z-report?
  Grain: business_date × store_id (every store-day the POS reported).
    status = OK        |diff| within tolerance (default 0.5%)
             MISMATCH  loaded, but totals differ
             MISSING   the POS reported sales but no lines reached the warehouse (late / failed file)
  The singular test tests/assert_pos_reconciliation_within_tolerance.sql fails `dbt build`
  when any store-day is not OK.
-#}
with

control as (
    select * from {{ ref('stg_pos__control_totals') }}
),

warehouse as (
    select
        sale_date,
        store_id,
        count(distinct transaction_id)  as wh_txn_count,
        count(*)                        as wh_line_count,
        sum(net_amount)                 as wh_net_amount
    from {{ ref('fct_sales_line') }}
    where sales_channel = 'STORE'
    group by 1, 2
)

select
    c.business_date,
    c.store_id,
    c.txn_count                                         as pos_txn_count,
    coalesce(w.wh_txn_count, 0)                         as wh_txn_count,
    c.line_count                                        as pos_line_count,
    coalesce(w.wh_line_count, 0)                        as wh_line_count,
    c.net_amount                                        as pos_net_amount,
    coalesce(w.wh_net_amount, 0)                        as wh_net_amount,
    coalesce(w.wh_net_amount, 0) - c.net_amount         as diff_amount,
    (coalesce(w.wh_net_amount, 0) - c.net_amount) / nullif(abs(c.net_amount), 0) as diff_pct,
    case
        when w.store_id is null then 'MISSING'
        when abs(coalesce(w.wh_net_amount, 0) - c.net_amount)
             <= {{ var('reconciliation_tolerance') }} * abs(c.net_amount) then 'OK'
        else 'MISMATCH'
    end                                                 as status,
    current_timestamp()                                 as checked_at
from control c
left join warehouse w
    on w.sale_date = c.business_date
   and w.store_id = c.store_id
