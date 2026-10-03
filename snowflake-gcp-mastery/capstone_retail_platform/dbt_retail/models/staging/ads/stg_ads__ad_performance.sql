with

source as (
    select * from {{ source('ads', 'ad_performance') }}
),

parsed as (
    select
        v:date::date                    as ad_date,
        lower(v:platform::varchar)      as platform,
        v:campaign_id::varchar          as campaign_id,
        v:campaign_name::varchar        as campaign_name,
        v:ad_id::varchar                as ad_id,
        v:ad_name::varchar              as ad_name,
        v:spend::number(12, 2)          as spend,
        v:currency::varchar             as currency,
        v:impressions::number           as impressions,
        v:clicks::number                as clicks,
        v:conversions::number           as conversions,
        _file_name,
        _loaded_at
    from source
)

select * from parsed
qualify row_number() over (partition by ad_date, ad_id order by _loaded_at desc, _file_name desc) = 1
