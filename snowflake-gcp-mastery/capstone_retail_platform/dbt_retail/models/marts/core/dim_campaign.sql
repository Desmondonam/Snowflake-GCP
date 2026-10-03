with

ads as (
    select * from {{ ref('stg_ads__ad_performance') }}
),

campaigns as (
    select
        campaign_id,
        max_by(campaign_name, ad_date)                          as campaign_name,
        max_by(platform, ad_date)                               as platform,
        min(ad_date)                                            as first_seen_date,
        max(ad_date)                                            as last_seen_date
    from ads
    group by campaign_id
)

select
    {{ dbt_utils.generate_surrogate_key(['campaign_id']) }} as campaign_sk,
    campaign_id,
    campaign_name,
    platform,
    iff(platform = 'google', 'paid_search', 'paid_social')  as channel_code,
    first_seen_date,
    last_seen_date
from campaigns

union all

-- email campaigns and unknown utm_campaign values have no ad-platform record
select '-1', 'UNKNOWN', 'Unknown / non-paid campaign', null, null, null, null
