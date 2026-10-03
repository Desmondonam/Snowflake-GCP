with

source as (
    select * from {{ source('pos', 'control_totals') }}
)

select
    business_date,
    store_id,
    txn_count,
    line_count,
    gross_amount::number(14, 2)     as gross_amount,
    discount_amount::number(14, 2)  as discount_amount,
    net_amount::number(14, 2)       as net_amount,
    _loaded_at
from source
qualify row_number() over (partition by business_date, store_id order by _loaded_at desc) = 1
