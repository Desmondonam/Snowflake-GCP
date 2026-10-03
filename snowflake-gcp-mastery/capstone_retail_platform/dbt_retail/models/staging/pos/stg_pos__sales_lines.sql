with

source as (
    select * from {{ source('pos', 'sales_lines') }}
),

renamed as (
    select
        transaction_id,
        line_no,
        store_id,
        sku,
        qty::number(10, 2)                      as quantity,
        unit_price::number(12, 2)               as unit_price,
        coalesce(discount, 0)::number(12, 2)    as discount_amount,
        nullif(trim(loyalty_id), '')            as loyalty_id,
        sold_at,
        nullif(trim(promo_code), '')            as promo_code,
        upper(tender_type)                      as tender_type,
        startswith(transaction_id, 'R-')        as is_return,
        _file_name,
        _file_row_number,
        _loaded_at
    from source
)

select * from renamed
-- stores sometimes re-send a file: keep one copy of each line, the most recently loaded
qualify row_number() over (
    partition by transaction_id, line_no
    order by _loaded_at desc, _file_name desc
) = 1
