select *
from {{ ref('stg_crm__customer_changes') }}
qualify row_number() over (partition by customer_id order by updated_at desc, _loaded_at desc) = 1
