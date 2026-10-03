with

source as (
    select * from {{ source('ecom', 'reviews') }}
)

select
    v:review_id::varchar            as review_id,
    v:sku::varchar                  as sku,
    v:customer_id::varchar          as customer_id,
    v:rating::number                as rating,
    v:review_text::varchar          as review_text,
    v:created_at::timestamp_ntz     as created_at,
    _loaded_at
from source
qualify row_number() over (partition by v:review_id::varchar order by _loaded_at desc) = 1
