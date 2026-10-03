{#-
  Activation audience: high-value customers who have stopped buying.
    high value = lifetime net sales in the top 20% of known customers
    lapsed     = no purchase in the 30 days before the latest sale date in the data
    consent    = marketing_consent must be true (never activate without consent)
  Pushed to Google Ads / Meta Customer Match by reverse ETL. Emails are masked by policy
  for everyone except the marketing role (Stage 7).
-#}
with

sales as (
    select customer_id, sale_date, net_amount
    from {{ ref('fct_sales_line') }}
    where customer_id <> '-1'
),

as_of as (
    select max(sale_date) as as_of_date from sales
),

per_customer as (
    select
        customer_id,
        sum(net_amount)          as lifetime_net,
        count(*)                 as lines,
        max(sale_date)           as last_purchase_date
    from sales
    group by 1
),

ranked as (
    select *, percent_rank() over (order by lifetime_net) as value_percentile
    from per_customer
),

current_customers as (
    select * from {{ ref('dim_customer') }} where is_current
)

select
    c.customer_id,
    c.email,
    c.phone,
    c.loyalty_tier,
    c.segment,
    c.country_code,
    r.lifetime_net,
    r.last_purchase_date,
    datediff('day', r.last_purchase_date, a.as_of_date)   as days_since_purchase,
    a.as_of_date
from ranked r
cross join as_of a
join current_customers c on c.customer_id = r.customer_id
where r.value_percentile >= 0.8
  and r.last_purchase_date < dateadd(day, -30, a.as_of_date)
  and c.marketing_consent
