{#-
  Marketing touchpoints we can tie to a known person: ad clicks, email opens and
  attributed page views from identified visitors (customer_email present).
-#}

with

events as (
    select * from {{ ref('stg_web__events') }}
    where customer_email is not null
      and event_type in ('ad_click', 'email_open', 'page_view')
      and channel is not null
),

identity as (
    select identifier_value as email, customer_id
    from {{ ref('int_customer_identity') }}
    where identifier_type = 'EMAIL'
)

select
    e.event_id                  as touchpoint_id,
    i.customer_id,
    e.event_ts                  as touched_at,
    e.event_type,
    e.channel,
    e.utm_source,
    e.utm_medium,
    e.utm_campaign              as campaign_id,
    e._loaded_at
from events e
join identity i on i.email = e.customer_email
