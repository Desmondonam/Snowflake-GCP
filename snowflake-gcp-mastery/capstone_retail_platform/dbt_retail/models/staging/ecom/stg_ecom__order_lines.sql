{#-
  The RAW table evolves: DELIVERY_METHOD only exists after the source added it.
  We ask Snowflake which columns exist right now, so this model compiles both
  before and after the schema change instead of failing.
-#}
{%- set source_relation = source('ecom', 'orders') -%}
{%- set source_columns = [] -%}
{%- if execute -%}  {#- only query Snowflake at run time, not while dbt parses the project -#}
    {%- set source_columns = adapter.get_columns_in_relation(source_relation) | map(attribute='name') | map('lower') | list -%}
{%- endif -%}

with

source as (
    select * from {{ source_relation }}
),

renamed as (
    select
        order_id,
        order_line,
        web_customer_id,
        lower(trim(customer_email))             as customer_email,
        sku,
        qty::number(10, 2)                      as quantity,
        unit_price::number(12, 2)               as unit_price,
        coalesce(discount, 0)::number(12, 2)    as discount_amount,
        ordered_at,
        upper(order_status)                     as order_status,
        ship_city,
        ship_country,
        {% if 'delivery_method' in source_columns -%}
        upper(delivery_method)                  as delivery_method,
        {%- else -%}
        null::varchar                           as delivery_method,
        {%- endif %}
        _file_name,
        _loaded_at
    from source
)

select * from renamed
qualify row_number() over (partition by order_id, order_line order by _loaded_at desc) = 1
