-- Grain: one identified marketing touch (ad click, email open, attributed page view).
with

touches as (select * from {{ ref('int_touchpoints') }}),
customers as (select * from {{ ref('dim_customer') }}),
campaigns as (select * from {{ ref('dim_campaign') }}),
channels as (select * from {{ ref('dim_channel') }})

select
    t.touchpoint_id,
    to_number(to_char(t.touched_at, 'YYYYMMDD'))   as date_key,
    t.touched_at,
    t.customer_id,
    coalesce(cu.customer_sk, '-1')                 as customer_sk,
    coalesce(ca.campaign_sk, '-1')                 as campaign_sk,
    t.campaign_id,
    ch.channel_sk,
    t.channel                                      as channel_code,
    t.event_type,
    t.utm_source,
    t.utm_medium
from touches t
left join customers cu
    on cu.customer_id = t.customer_id
   and t.touched_at >= cu.valid_from and t.touched_at < cu.valid_to
left join campaigns ca on ca.campaign_id = t.campaign_id
left join channels ch  on ch.channel_code = t.channel
