with

source as (
    select * from {{ source('crm', 'customers') }}
),

parsed as (
    select
        v:customer_id::varchar              as customer_id,
        nullif(v:loyalty_id::varchar, '')   as loyalty_id,
        lower(trim(v:email::varchar))       as email,
        v:phone::varchar                    as phone,
        v:first_name::varchar               as first_name,
        v:last_name::varchar                as last_name,
        v:birth_date::date                  as birth_date,
        v:city::varchar                     as city,
        v:country_code::varchar             as country_code,
        upper(v:segment::varchar)           as segment,
        upper(v:loyalty_tier::varchar)      as loyalty_tier,
        v:marketing_consent::boolean        as marketing_consent,
        v:created_at::timestamp_ntz         as created_at,
        v:updated_at::timestamp_ntz         as updated_at,
        _file_name,
        _loaded_at
    from source
)

select * from parsed
qualify row_number() over (partition by customer_id, updated_at order by _loaded_at desc) = 1
