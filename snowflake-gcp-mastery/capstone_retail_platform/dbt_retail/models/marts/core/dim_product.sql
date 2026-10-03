-- SCD Type 2 product dimension: margin must use the cost and price valid at the time of sale.
with

versions as (
    select * from {{ ref('int_product_versions') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['sku', 'valid_from']) }}  as product_sk,
    sku,
    product_name,
    category,
    subcategory,
    brand,
    unit_cost,
    list_price,
    valid_from,
    valid_to,
    is_current
from versions

union all

-- unknown member: facts whose SKU is missing from the product master still join
select '-1', 'UNKNOWN', 'Unknown product', 'UNKNOWN', 'UNKNOWN', 'UNKNOWN', 0, 0,
       '1900-01-01'::timestamp_ntz, '9999-12-31'::timestamp_ntz, true
