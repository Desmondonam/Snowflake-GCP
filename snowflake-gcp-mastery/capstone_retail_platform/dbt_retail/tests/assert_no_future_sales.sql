-- A sale dated in the future means a clock or timezone problem at the source.
{{ config(severity='warn') }}

select sales_line_key, sold_at
from {{ ref('fct_sales_line') }}
where sold_at > dateadd(day, 1, current_timestamp()::timestamp_ntz)
