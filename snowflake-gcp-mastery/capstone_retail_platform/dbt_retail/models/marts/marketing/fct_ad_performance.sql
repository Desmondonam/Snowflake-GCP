-- Grain: ad × day. Store additive parts only; CTR / CPC / ROAS are computed at query time.
with

ads as (select * from {{ ref('stg_ads__ad_performance') }}),
campaigns as (select * from {{ ref('dim_campaign') }}),
channels as (select * from {{ ref('dim_channel') }})

select
    {{ dbt_utils.generate_surrogate_key(['a.ad_date', 'a.ad_id']) }}   as ad_performance_key,
    to_number(to_char(a.ad_date, 'YYYYMMDD'))                         as date_key,
    a.ad_date,
    coalesce(c.campaign_sk, '-1')                                     as campaign_sk,
    a.campaign_id,
    a.ad_id,
    a.ad_name,
    a.platform,
    ch.channel_sk,
    ch.channel_code,
    a.spend,
    a.impressions,
    a.clicks,
    a.conversions
from ads a
left join campaigns c on c.campaign_id = a.campaign_id
left join channels ch on ch.channel_code = iff(a.platform = 'google', 'paid_search', 'paid_social')
