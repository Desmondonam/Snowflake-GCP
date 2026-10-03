{#-
  SCD Type 2 versions of each CRM customer, rebuilt from the full change history in RAW.
  Tracked (Type 2): segment, loyalty_tier, city, country_code.
  Everything else is Type 1 and taken from the latest record in dim_customer.
-#}
{{ scd2_from_changes(
    relation=ref('stg_crm__customer_changes'),
    natural_key='customer_id',
    changed_at='updated_at',
    tracked_cols=['segment', 'loyalty_tier', 'city', 'country_code']
) }}
