-- Last-click attribution: 100% of the order's revenue goes to the most recent touch before the order.
with

touches as (select * from {{ ref('int_order_touchpoints') }})

select
    order_id,
    customer_id,
    ordered_at,
    touchpoint_id,
    touched_at,
    channel,
    campaign_id,
    1::number(10, 6)                    as credit,
    order_net::number(14, 2)            as attributed_revenue,
    'last_click'                        as attribution_model
from touches
qualify row_number() over (partition by order_id order by touched_at desc nulls last, touchpoint_id) = 1
