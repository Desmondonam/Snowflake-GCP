with

source as (
    select * from {{ source('erp', 'inventory') }}
)

select
    snapshot_date,
    store_id,
    sku,
    opening_qty::number(12, 2)  as opening_qty,
    _loaded_at
from source
qualify row_number() over (partition by snapshot_date, store_id, sku order by _loaded_at desc) = 1
