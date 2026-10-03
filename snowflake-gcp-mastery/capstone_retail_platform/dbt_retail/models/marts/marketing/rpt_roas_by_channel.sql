-- Marketing ROI by day × channel × campaign × attribution model.
-- ROAS = attributed revenue / ad spend. Only paid channels have spend; ROAS is NULL elsewhere.
with

revenue as (
    select
        ordered_at::date            as report_date,
        attribution_model,
        channel_code,
        campaign_id,
        sum(credit)                 as attributed_orders,
        sum(attributed_revenue)     as attributed_revenue
    from {{ ref('fct_attribution') }}
    group by 1, 2, 3, 4
),

spend as (
    select ad_date as report_date, campaign_id, sum(spend) as spend, sum(clicks) as clicks, sum(impressions) as impressions
    from {{ ref('fct_ad_performance') }}
    group by 1, 2
)

select
    r.report_date,
    r.attribution_model,
    r.channel_code,
    r.campaign_id,
    r.attributed_orders,
    r.attributed_revenue,
    s.spend,
    s.clicks,
    s.impressions,
    r.attributed_revenue / nullif(s.spend, 0)       as roas
from revenue r
left join spend s
    on s.report_date = r.report_date
   and s.campaign_id = r.campaign_id
