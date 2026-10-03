with

source as (
    select * from {{ source('erp', 'products') }}
)

select
    sku,
    product_name,
    category,
    subcategory,
    brand,
    unit_cost::number(12, 2)    as unit_cost,
    list_price::number(12, 2)   as list_price,
    updated_at,
    _loaded_at
from source
qualify row_number() over (partition by sku, updated_at order by _loaded_at desc) = 1
