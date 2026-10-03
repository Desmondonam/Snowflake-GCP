{#-
  fct_sales_line — grain: ONE ROW PER SALES LINE (store receipt line or online order line).

  Incremental (merge on sales_line_key):
    * normal run  : reprocess lines loaded in the last `lookback_days` (late files, re-sends)
    * backfill    : dbt build -s fct_sales_line --vars '{backfill_start: "2026-08-01", backfill_end: "2026-08-31"}'
                    reprocesses a sale-date range without a full refresh
    * full rebuild: dbt build -s fct_sales_line --full-refresh
  Clustered on (sale_date, store_id) because almost every query filters on date and store.
-#}
{{ config(
    materialized='incremental',
    unique_key='sales_line_key',
    incremental_strategy='merge',
    on_schema_change='append_new_columns',
    cluster_by=['sale_date', 'store_id'],
    snowflake_warehouse='TRANSFORM_WH'
) }}

with

lines as (
    select * from {{ ref('int_sales_lines_unioned') }}
    {% if is_incremental() %}
        {% if var('backfill_start', none) is not none %}
    where sold_at::date between '{{ var("backfill_start") }}' and '{{ var("backfill_end", var("backfill_start")) }}'
        {% else %}
    where _loaded_at > (
        select dateadd(day, -{{ var('lookback_days') }}, coalesce(max(_loaded_at), '1900-01-01'::timestamp_ltz))
        from {{ this }}
    )
        {% endif %}
    {% endif %}
),

stores as (select * from {{ ref('dim_store') }}),
products as (select * from {{ ref('dim_product') }}),
customers as (select * from {{ ref('dim_customer') }}),
promotions as (select * from {{ ref('dim_promotion') }}),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['l.sales_channel', 'l.transaction_id', 'l.line_no']) }}
                                                                    as sales_line_key,
        l.sales_channel,
        l.transaction_id,
        l.line_no,
        to_number(to_char(l.sold_at, 'YYYYMMDD'))                   as date_key,
        l.sold_at::date                                             as sale_date,
        l.sold_at,
        s.store_sk,
        l.store_id,
        coalesce(s.region, l.region_override)                       as store_region,
        coalesce(p.product_sk, '-1')                                as product_sk,
        l.sku,
        coalesce(c.customer_sk, '-1')                               as customer_sk,
        coalesce(l.customer_id, '-1')                               as customer_id,
        coalesce(pr.promotion_sk, {{ dbt_utils.generate_surrogate_key(["'NONE'"]) }}) as promotion_sk,
        l.quantity,
        l.unit_price,
        (l.quantity * l.unit_price)                                 as gross_amount,
        l.discount_amount,
        (l.quantity * l.unit_price - l.discount_amount)             as net_amount,
        (l.quantity * coalesce(p.unit_cost, 0))                     as cost_amount,
        (l.quantity * l.unit_price - l.discount_amount
           - l.quantity * coalesce(p.unit_cost, 0))                 as margin_amount,
        l.quantity < 0                                              as is_return,
        l._loaded_at,
        current_timestamp()                                         as _dbt_updated_at
    from lines l
    left join stores s
        on s.store_id = l.store_id
    left join products p                                            -- price/cost valid AT sale time
        on p.sku = l.sku
       and l.sold_at >= p.valid_from and l.sold_at < p.valid_to
    left join customers c                                           -- tier/segment valid AT sale time
        on c.customer_id = l.customer_id
       and l.sold_at >= c.valid_from and l.sold_at < c.valid_to
    left join promotions pr
        on pr.promo_code = l.promo_code
)

select
    sales_line_key::varchar             as sales_line_key,
    sales_channel::varchar              as sales_channel,
    transaction_id::varchar             as transaction_id,
    line_no::number                     as line_no,
    date_key::number                    as date_key,
    sale_date::date                     as sale_date,
    sold_at::timestamp_ntz              as sold_at,
    store_sk::varchar                   as store_sk,
    store_id::varchar                   as store_id,
    store_region::varchar               as store_region,
    product_sk::varchar                 as product_sk,
    sku::varchar                        as sku,
    customer_sk::varchar                as customer_sk,
    customer_id::varchar                as customer_id,
    promotion_sk::varchar               as promotion_sk,
    quantity::number(10, 2)             as quantity,
    unit_price::number(12, 2)           as unit_price,
    gross_amount::number(14, 2)         as gross_amount,
    discount_amount::number(14, 2)      as discount_amount,
    net_amount::number(14, 2)           as net_amount,
    cost_amount::number(14, 2)          as cost_amount,
    margin_amount::number(14, 2)        as margin_amount,
    is_return::boolean                  as is_return,
    _loaded_at::timestamp_ltz           as _loaded_at,
    _dbt_updated_at::timestamp_ltz      as _dbt_updated_at
from final
