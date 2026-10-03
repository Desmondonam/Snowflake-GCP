with

source as (
    select * from {{ source('erp', 'stores') }}
)

select
    store_id,
    store_name,
    city,
    country_code,
    region,
    opened_date,
    size_sqm,
    updated_at
from source
qualify row_number() over (partition by store_id order by updated_at desc, _loaded_at desc) = 1
