{{ config(materialized='table') }}

{#-
  Identity resolution: map every identifier we see to ONE customer_id.

     identifier_type  identifier_value               customer_id   customer_source
     CUSTOMER_ID      C00042                         C00042        CRM
     LOYALTY_ID       L000042                        C00042        CRM      ← POS sales arrive with this
     EMAIL            larry.tate.42@example.com      C00042        CRM      ← online orders / web events
     EMAIL            guest00017@example.net         G-1a2b3c4d5e  GUEST    ← guest checkout, not in CRM

  Deterministic matching only (exact keys). Probabilistic matching (name + phone + address,
  with a confidence score) would be the next step in a real project.
-#}

with

crm as (
    select customer_id, loyalty_id, email from {{ ref('stg_crm__customers') }}
),

seen_emails as (
    select customer_email as email from {{ ref('stg_ecom__order_lines') }} where customer_email is not null
    union
    select customer_email from {{ ref('stg_web__events') }} where customer_email is not null
),

guests as (
    select
        'G-' || left(md5(e.email), 10)  as customer_id,
        e.email
    from seen_emails e
    left join crm c on c.email = e.email
    where c.customer_id is null
),

identity_map as (
    select customer_id, 'CUSTOMER_ID' as identifier_type, customer_id as identifier_value, 'CRM' as customer_source from crm
    union all
    select customer_id, 'LOYALTY_ID', loyalty_id, 'CRM' from crm where loyalty_id is not null
    union all
    select customer_id, 'EMAIL', email, 'CRM' from crm where email is not null
    union all
    select customer_id, 'EMAIL', email, 'GUEST' from guests
)

select * from identity_map
