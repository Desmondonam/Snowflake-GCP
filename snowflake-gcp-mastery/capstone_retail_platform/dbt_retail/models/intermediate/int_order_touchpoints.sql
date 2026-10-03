{#-
  Attribution input. One row per (online order × touchpoint in the lookback window).
  Orders with no qualifying touch get ONE row with channel = 'unattributed', so every
  order's revenue is fully distributed by every attribution model.
  Columns: order_id, customer_id, ordered_at, order_net, touchpoint_id, touched_at,
           channel, campaign_id, hours_before_order
-#}

with

orders as (
    select
        transaction_id      as order_id,
        customer_id,
        min(sold_at)        as ordered_at,
        sum(quantity * unit_price - discount_amount) as order_net
    from {{ ref('int_sales_lines_unioned') }}
    where sales_channel = 'ONLINE'
    group by 1, 2
    having sum(quantity * unit_price - discount_amount) > 0   -- returned orders don't earn attribution credit
),

touches as (
    select * from {{ ref('int_touchpoints') }}
),

joined as (
    select
        o.order_id,
        o.customer_id,
        o.ordered_at,
        o.order_net,
        t.touchpoint_id,
        t.touched_at,
        t.channel,
        t.campaign_id
    from orders o
    left join touches t
        on t.customer_id = o.customer_id
       and t.touched_at <  o.ordered_at
       and t.touched_at >= dateadd(day, -{{ var('attribution_window_days') }}, o.ordered_at)
)

select
    order_id,
    customer_id,
    ordered_at,
    order_net::number(14, 2)                        as order_net,
    touchpoint_id,
    touched_at,
    coalesce(channel, 'unattributed')               as channel,
    campaign_id,
    datediff('minute', touched_at, ordered_at) / 60 as hours_before_order
from joined
