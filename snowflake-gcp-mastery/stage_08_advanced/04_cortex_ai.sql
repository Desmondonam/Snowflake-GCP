/* =============================================================================
   Stage 8 · Lesson 04 — Snowflake Cortex AI on product reviews
   -----------------------------------------------------------------------------
   LLM functions callable from SQL, running inside Snowflake (data never leaves):
     SNOWFLAKE.CORTEX.SENTIMENT(text)                → -1 .. 1
     SNOWFLAKE.CORTEX.SUMMARIZE(text)                → short summary
     SNOWFLAKE.CORTEX.CLASSIFY_TEXT(text, [labels])  → {"label": …}
     SNOWFLAKE.CORTEX.COMPLETE(model, prompt)        → free-form generation
   Newer AI_* names (AI_SENTIMENT, AI_CLASSIFY, AI_COMPLETE, AI_AGG …) cover the same ground —
   check the docs for what your account has. Availability of models varies by region and changes often.

   COST: billed per token in credits. Always LIMIT while experimenting; score each review ONCE (incremental).
   HOW TO RUN: worksheet, statement by statement.
   ============================================================================= */

-- 0. If a function/model isn't available in GCP us-central1, allow cross-region inference (ACCOUNTADMIN):
-- USE ROLE ACCOUNTADMIN;
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
-- (The SNOWFLAKE.CORTEX_USER database role is granted to PUBLIC by default.)

USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE TRANSFORM_WH;

-- 1. Sentiment vs the star rating: does the model agree with customers?
SELECT review_id, rating, review_text,
       ROUND(SNOWFLAKE.CORTEX.SENTIMENT(review_text), 2) AS sentiment
FROM RETAIL_STAGING.ECOM.STG_ECOM__REVIEWS
ORDER BY created_at DESC
LIMIT 20;

-- 2. What are complaints about? (classification into business categories)
SELECT review_id, rating, review_text,
       SNOWFLAKE.CORTEX.CLASSIFY_TEXT(review_text,
         ['product quality', 'delivery', 'price', 'customer service'])['label']::STRING AS topic
FROM RETAIL_STAGING.ECOM.STG_ECOM__REVIEWS
WHERE rating <= 2
ORDER BY created_at DESC
LIMIT 20;

-- 3. One summary per product across its reviews (aggregate text first, then summarise once)
WITH per_sku AS (
  SELECT sku, COUNT(*) AS n, LISTAGG(review_text, ' ') WITHIN GROUP (ORDER BY created_at DESC) AS all_text
  FROM RETAIL_STAGING.ECOM.STG_ECOM__REVIEWS
  GROUP BY sku
  HAVING COUNT(*) >= 8
)
SELECT sku, n, SNOWFLAKE.CORTEX.SUMMARIZE(all_text) AS review_summary
FROM per_sku
ORDER BY n DESC
LIMIT 5;

-- 4. Generation: a suggested action for the store team (pick a model available to you)
SELECT review_id, review_text,
       SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b',
         'You are a retail operations assistant. In one sentence, suggest an action for the store team based on this review: '
         || review_text) AS suggested_action
FROM RETAIL_STAGING.ECOM.STG_ECOM__REVIEWS
WHERE rating = 1
LIMIT 5;

/* ---------------------------------------------------------------------------
   5. Production: score every review once, incrementally, in dbt
      cd capstone_retail_platform\dbt_retail
      dbt build --target prod -s product_review_scores --vars "{enable_cortex: true}"
   Then a product quality score per SKU (used by the Streamlit app):
   --------------------------------------------------------------------------- */
SELECT p.sku, p.product_name, p.brand,
       COUNT(*)                     AS reviews,
       ROUND(AVG(s.rating), 2)      AS avg_rating,
       ROUND(AVG(s.sentiment), 3)   AS avg_sentiment,
       ROUND(50 * (AVG(s.sentiment) + 1), 0) AS quality_score_0_100
FROM RETAIL_MARTS.CORE.PRODUCT_REVIEW_SCORES s
JOIN RETAIL_MARTS.CORE.DIM_PRODUCT p ON p.sku = s.sku AND p.is_current
GROUP BY 1, 2, 3
HAVING COUNT(*) >= 5
ORDER BY quality_score_0_100 ASC
LIMIT 20;

-- 6. What did it cost? (ACCOUNT_USAGE, lags a few hours)
USE ROLE RETAIL_ADMIN;
SELECT function_name, model_name, SUM(tokens) AS tokens, SUM(token_credits) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE start_time > DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2 ORDER BY credits DESC;

/* Beyond functions (know what they are for the interview):
   * Cortex Search      — hybrid vector + keyword search service over text (RAG on product manuals, policies)
   * Cortex Analyst     — natural language → SQL over a semantic model of your marts ("sales in Doha last week?")
   * Snowflake ML       — feature store, model registry, ML functions (FORECAST for demand, ANOMALY_DETECTION)
   * Snowpark Container Services — run any container (custom models, APIs) next to the data */
