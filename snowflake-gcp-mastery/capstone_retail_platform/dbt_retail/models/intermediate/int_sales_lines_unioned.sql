{#-
  Store and online sales in one shape, with the customer resolved through the identity map.
  Grain: one sales line (store: transaction_id + line_no; online: order_id + order_line).
  Cancelled online orders are not sales. Returned online orders become negative lines,
  the same way store returns are negative lines.
-#}

with

identity as (
    select identifier_type, identifier_value, customer_id from {{ ref('int_customer_identity') }}
),

store_lines as (
    select
        'STORE'                         as sales_channel,
        transaction_id,
        line_no,
        store_id,
        sku,
        quantity,
        unit_price,
        discount_amount,
        promo_code,
        sold_at,
        null::varchar                   as region_override,
        loyalty_id                      as identity_value,
        'LOYALTY_ID'                    as identity_type,
        _loaded_at
    from {{ ref('stg_pos__sales_lines') }}
),

online_lines as (
    select
        'ONLINE'                        as sales_channel,
        order_id                        as transaction_id,
        order_line                      as line_no,
        'ONLINE'                        as store_id,
        sku,
        iff(order_status = 'RETURNED', -quantity, quantity)               as quantity,
        unit_price,
        iff(order_status = 'RETURNED', -discount_amount, discount_amount) as discount_amount,
        null::varchar                   as promo_code,
        ordered_at                      as sold_at,
        ship_country                    as region_override,
        customer_email                  as identity_value,
        'EMAIL'                         as identity_type,
        _loaded_at
    from {{ ref('stg_ecom__order_lines') }}
    where order_status <> 'CANCELLED'
),

unioned as (
    select * from store_lines
    union all
    select * from online_lines
)

select
    u.*,
    i.customer_id
from unioned u
left join identity i
    on i.identifier_type = u.identity_type
   and i.identifier_value = u.identity_value
