{#-
  The conformed customer dimension, unified across store (loyalty card) and online (email).
    CRM customers : SCD2 history of segment / tier / city / country (int_customer_versions)
                    + Type 1 contact details from the latest record
    Guests        : one version each (online checkouts that aren't in the CRM)
    Unknown       : '-1' for anonymous store shoppers
  Contract enforced: column names and types are an API for BI tools.
-#}
{{ config(contract={'enforced': true}) }}

with

versions as (
    select * from {{ ref('int_customer_versions') }}
),

latest as (
    select * from {{ ref('stg_crm__customers') }}
),

guests as (
    select distinct customer_id, identifier_value as email
    from {{ ref('int_customer_identity') }}
    where customer_source = 'GUEST'
),

crm_customers as (
    select
        {{ dbt_utils.generate_surrogate_key(['v.customer_id', 'v.valid_from']) }} as customer_sk,
        v.customer_id,
        'CRM'                   as customer_source,
        l.loyalty_id,
        l.email,
        l.phone,
        l.first_name,
        l.last_name,
        l.birth_date,
        v.city,
        v.country_code,
        v.segment,
        v.loyalty_tier,
        l.marketing_consent,
        v.valid_from,
        v.valid_to,
        v.is_current
    from versions v
    join latest l on l.customer_id = v.customer_id
),

guest_customers as (
    select
        {{ dbt_utils.generate_surrogate_key(['customer_id', "'1900-01-01 00:00:00.000'"]) }},
        customer_id, 'GUEST', null, email, null, null, null, null, null, null,
        'GUEST', null, false,
        '1900-01-01'::timestamp_ntz, '9999-12-31'::timestamp_ntz, true
    from guests
),

unknown_customer as (
    select '-1', '-1', 'UNKNOWN', null, null, null, null, null, null, null, null,
           'UNKNOWN', null, false,
           '1900-01-01'::timestamp_ntz, '9999-12-31'::timestamp_ntz, true
),

unioned as (
    select * from crm_customers
    union all
    select * from guest_customers
    union all
    select * from unknown_customer
)

select
    customer_sk::varchar            as customer_sk,
    customer_id::varchar            as customer_id,
    customer_source::varchar        as customer_source,
    loyalty_id::varchar             as loyalty_id,
    email::varchar                  as email,
    phone::varchar                  as phone,
    first_name::varchar             as first_name,
    last_name::varchar              as last_name,
    birth_date::date                as birth_date,
    city::varchar                   as city,
    country_code::varchar           as country_code,
    segment::varchar                as segment,
    loyalty_tier::varchar           as loyalty_tier,
    marketing_consent::boolean      as marketing_consent,
    valid_from::timestamp_ntz       as valid_from,
    valid_to::timestamp_ntz         as valid_to,
    is_current::boolean             as is_current
from unioned
