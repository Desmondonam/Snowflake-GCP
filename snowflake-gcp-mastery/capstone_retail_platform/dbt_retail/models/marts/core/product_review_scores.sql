{#-
  Stage 8: product quality score from review text using Snowflake Cortex.
  Disabled by default (costs AI credits). Enable with:
      dbt build -s product_review_scores --vars '{enable_cortex: true}'
  or set enable_cortex: true in dbt_project.yml.
  Incremental: each review is scored ONCE; only new reviews call the model.
  Check Cortex availability in your region first (stage_08_advanced/04_cortex_ai.sql).
-#}
{{ config(
    enabled=var('enable_cortex', false),
    materialized='incremental',
    unique_key='review_id'
) }}

with

reviews as (
    select * from {{ ref('stg_ecom__reviews') }}
    {% if is_incremental() %}
    where review_id not in (select review_id from {{ this }})
    {% endif %}
)

select
    review_id,
    sku,
    customer_id,
    rating,
    review_text,
    created_at,
    snowflake.cortex.sentiment(review_text)::float      as sentiment,   -- -1 (negative) .. 1 (positive)
    current_timestamp()                                 as scored_at
from reviews
