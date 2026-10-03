select
    {{ dbt_utils.generate_surrogate_key(['promo_code']) }} as promotion_sk,
    promo_code,
    promo_name,
    promo_type,
    discount_pct
from {{ ref('promotions') }}
