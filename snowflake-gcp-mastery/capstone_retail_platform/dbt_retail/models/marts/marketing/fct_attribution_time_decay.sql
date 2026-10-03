{#-
  Time-decay attribution: touches closer to the order earn more credit.
    weight = 0.5 ^ (hours_before_order / half_life)     (half_life = var time_decay_half_life_hours)
    credit = weight / sum(weight) over the order        (credits sum to exactly 1 per order)
  Unattributed orders (no touches) get weight 1 → credit 1.
-#}
with

touches as (select * from {{ ref('int_order_touchpoints') }}),

weighted as (
    select
        *,
        iff(touched_at is null, 1,
            power(0.5, hours_before_order / {{ var('time_decay_half_life_hours') }})) as weight
    from touches
)

select
    order_id,
    customer_id,
    ordered_at,
    touchpoint_id,
    touched_at,
    channel,
    campaign_id,
    (weight / sum(weight) over (partition by order_id))::number(10, 6)              as credit,
    (order_net * weight / sum(weight) over (partition by order_id))::number(14, 2)  as attributed_revenue,
    'time_decay'                                                                     as attribution_model
from weighted
