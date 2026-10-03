select
    {{ dbt_utils.generate_surrogate_key(['channel_code']) }} as channel_sk,
    channel_code,
    channel_name,
    channel_group,
    is_paid
from {{ ref('channels') }}
