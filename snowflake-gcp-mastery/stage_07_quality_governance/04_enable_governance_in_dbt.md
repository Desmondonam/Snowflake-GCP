# Step 04 — Keep governance in code: turn on the dbt post-hook

dbt rebuilds most mart tables with `CREATE OR REPLACE`, which **drops tags and row access policies**. The macro
[apply_governance.sql](../capstone_retail_platform/dbt_retail/macros/apply_governance.sql) runs after every mart model
and re-applies them from YAML metadata:

```yaml
# models/marts/core/_core.yml
- name: email
  config:
    meta: {pii: email}            # → ALTER TABLE … MODIFY COLUMN email SET TAG GOV.TAGS.PII = 'email'

# models/marts/sales/_sales.yml
config:
  meta:
    row_access_policy: {name: GOV.POLICIES.RAP_STORE_REGION, column: store_region}
```

## Turn it on

1. Steps 01–03 done (tag, policies, grants to `RETAIL_ENGINEER` exist).
2. In [dbt_project.yml](../capstone_retail_platform/dbt_retail/dbt_project.yml) set `enable_governance: true`.
3. Rebuild prod:

   ```powershell
   cd capstone_retail_platform\dbt_retail
   dbt build --target prod
   ```

4. Check that tags and the policy survived the rebuild:

   ```sql
   SELECT column_name, tag_value
   FROM TABLE(RETAIL_MARTS.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('RETAIL_MARTS.CORE.DIM_CUSTOMER', 'table'));

   SELECT policy_name, ref_column_name
   FROM TABLE(RETAIL_MARTS.INFORMATION_SCHEMA.POLICY_REFERENCES(
     REF_ENTITY_NAME => 'RETAIL_MARTS.SALES.FCT_SALES_LINE', REF_ENTITY_DOMAIN => 'table'));
   ```

## Why not let governance live only in the SQL scripts?

Because the next `dbt build` would silently remove it. "Governance as code" means the classification lives next to the
column definition, is reviewed in pull requests, and is re-applied on every deploy. The **policy logic** stays owned by
`GOVERNANCE_ADMIN` in the `GOV` database (separation of duties): engineers can *apply* the tag, not change what it does.

## What about dev and CI?

In dev (`RETAIL_DEV`) the hook applies the same tags, so you develop against masked data exactly as users see it.
In CI clones, tags and policies are cloned with the tables.
