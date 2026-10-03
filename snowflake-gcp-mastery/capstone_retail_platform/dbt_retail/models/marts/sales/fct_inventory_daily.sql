{#-
  fct_inventory_daily — PERIODIC SNAPSHOT. Grain: store × sku × day.
  closing_qty is SEMI-ADDITIVE: sum across stores/products, never across days.
  Incremental by snapshot_date with a lookback, because late POS files change units_sold.
-#}
{{ config(
    materialized='incremental',
    unique_key='inventory_key',
    incremental_strategy='merge',
    cluster_by=['snapshot_date', 'store_id']
) }}

with

inventory as (
    select * from {{ ref('stg_erp__inventory') }}
    {% if is_incremental() %}
    where snapshot_date >= (
        select dateadd(day, -{{ var('lookback_days') }}, coalesce(max(snapshot_date), '1900-01-01'::date))
        from {{ this }}
    )
    {% endif %}
),

sold as (
    select store_id, sku, sale_date, sum(quantity) as units_sold
    from {{ ref('fct_sales_line') }}
    where sales_channel = 'STORE'
    {% if is_incremental() %}
      and sale_date >= (select dateadd(day, -{{ var('lookback_days') }}, coalesce(max(snapshot_date), '1900-01-01'::date)) from {{ this }})
    {% endif %}
    group by 1, 2, 3
),

stores as (select * from {{ ref('dim_store') }}),
products as (select * from {{ ref('dim_product') }})

select
    {{ dbt_utils.generate_surrogate_key(['i.snapshot_date', 'i.store_id', 'i.sku']) }} as inventory_key,
    to_number(to_char(i.snapshot_date, 'YYYYMMDD'))                     as date_key,
    i.snapshot_date,
    s.store_sk,
    i.store_id,
    s.region                                                            as store_region,
    coalesce(p.product_sk, '-1')                                        as product_sk,
    i.sku,
    i.opening_qty,
    coalesce(sold.units_sold, 0)::number(12, 2)                         as units_sold,
    (i.opening_qty - coalesce(sold.units_sold, 0))::number(12, 2)       as closing_qty,
    current_timestamp()                                                 as _dbt_updated_at
from inventory i
left join sold
    on sold.store_id = i.store_id and sold.sku = i.sku and sold.sale_date = i.snapshot_date
left join stores s
    on s.store_id = i.store_id
left join products p
    on p.sku = i.sku
   and i.snapshot_date::timestamp_ntz >= p.valid_from
   and i.snapshot_date::timestamp_ntz < p.valid_to
