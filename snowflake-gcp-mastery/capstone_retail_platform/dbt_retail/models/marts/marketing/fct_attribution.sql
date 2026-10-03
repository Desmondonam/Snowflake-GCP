-- All attribution models in one fact. Grain: attribution_model × order × touchpoint.
-- Pick a model in the BI tool with a filter; credits sum to 1 per order per model.
{% set models = ['fct_attribution_last_click', 'fct_attribution_linear', 'fct_attribution_time_decay'] %}

with

unioned as (
    {% for m in models %}
    select
        attribution_model, order_id, customer_id, ordered_at, touchpoint_id, touched_at,
        channel, campaign_id, credit, attributed_revenue
    from {{ ref(m) }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select
    {{ dbt_utils.generate_surrogate_key(['attribution_model', 'order_id', 'touchpoint_id']) }} as attribution_key,
    attribution_model::varchar                       as attribution_model,
    order_id::varchar                                as order_id,
    customer_id::varchar                             as customer_id,
    to_number(to_char(ordered_at, 'YYYYMMDD'))       as order_date_key,
    ordered_at::timestamp_ntz                        as ordered_at,
    touchpoint_id::varchar                           as touchpoint_id,
    touched_at::timestamp_ntz                        as touched_at,
    channel::varchar                                 as channel_code,
    campaign_id::varchar                             as campaign_id,
    credit::number(10, 6)                            as credit,
    attributed_revenue::number(14, 2)                as attributed_revenue
from unioned
