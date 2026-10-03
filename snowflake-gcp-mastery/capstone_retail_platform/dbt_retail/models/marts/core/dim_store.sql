-- SCD Type 1: store attributes are overwritten. One extra member represents the web shop.
with

stores as (
    select * from {{ ref('stg_erp__stores') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['store_id']) }}   as store_sk,
    store_id,
    store_name,
    city,
    country_code,
    region,
    opened_date,
    size_sqm,
    'PHYSICAL'                                             as store_type
from stores

union all

select
    {{ dbt_utils.generate_surrogate_key(["'ONLINE'"]) }},
    'ONLINE', 'RetailOne Online', null, null, null, null, null, 'ONLINE'
