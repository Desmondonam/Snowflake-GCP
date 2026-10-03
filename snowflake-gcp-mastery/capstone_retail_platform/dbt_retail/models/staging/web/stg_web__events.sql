with

source as (
    select * from {{ source('web', 'events') }}
),

parsed as (
    select
        v:event_id::varchar                         as event_id,
        v:event_ts::timestamp_ntz                   as event_ts,
        v:event_type::varchar                       as event_type,
        v:anonymous_id::varchar                     as anonymous_id,
        lower(trim(v:customer_email::varchar))      as customer_email,
        v:channel::varchar                          as channel,
        v:utm_source::varchar                       as utm_source,
        v:utm_medium::varchar                       as utm_medium,
        v:utm_campaign::varchar                     as utm_campaign,
        v:page::varchar                             as page,
        v:order_id::varchar                         as order_id,
        _loaded_at
    from source
)

select * from parsed
qualify row_number() over (partition by event_id order by _loaded_at desc) = 1
