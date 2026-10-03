with

spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2024-01-01' as date)",
        end_date="cast('2028-01-01' as date)"
    ) }}
)

select
    to_number(to_char(date_day, 'YYYYMMDD'))    as date_key,
    date_day::date                              as date_day,
    year(date_day)                              as year,
    quarter(date_day)                           as quarter,
    month(date_day)                             as month,
    monthname(date_day)                         as month_name,
    weekiso(date_day)                           as iso_week,
    date_trunc('week', date_day)::date          as week_start,
    date_trunc('month', date_day)::date         as month_start,
    dayofweekiso(date_day)                      as day_of_week_iso,
    dayname(date_day)                           as day_name,
    dayofweekiso(date_day) in (6, 7)            as is_weekend_ke,   -- Sat/Sun
    dayofweekiso(date_day) in (5, 6)            as is_weekend_qa    -- Fri/Sat
from spine
