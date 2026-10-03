# Stage 7 — Data quality, security and governance (week 8)

**Goal:** lock RetailOne down the way a regulated retailer would: a scalable role design, PII masked by classification tag,
regional row-level security, quality measured continuously, and the ability to prove to an auditor who saw what.

**Prerequisites:** Capstone 4 built with `--target prod` (RETAIL_MARTS schemas exist), Capstone 5.

| # | File | What you build | Run as |
| --- | --- | --- | --- |
| 01 | [01_rbac_roles.sql](01_rbac_roles.sql) | Access roles, functional roles, GOV database, managed access, the future-grants gotcha | system roles (Run All) |
| 02 | [02_tags_and_masking.sql](02_tags_and_masking.sql) | `GOV.TAGS.PII` + tag-based masking (string + date) | GOVERNANCE_ADMIN |
| 03 | [03_row_access_policy.sql](03_row_access_policy.sql) | Mapping table + `RAP_STORE_REGION` on `fct_sales_line` | GOVERNANCE_ADMIN |
| 04 | [04_enable_governance_in_dbt.md](04_enable_governance_in_dbt.md) | dbt post-hook re-applies tags and policies on every build | dbt |
| 05 | [05_data_metric_functions.sql](05_data_metric_functions.sql) | DMFs on the two biggest tables (system + custom) | RETAIL_ENGINEER |
| 06 | [06_audit_and_lineage.sql](06_audit_and_lineage.sql) | ACCESS_HISTORY, TAG/POLICY_REFERENCES, dependencies, logins | GOVERNANCE_ADMIN |
| 07 | [07_test_as_each_role.sql](07_test_as_each_role.sql) | Prove what each role sees (screenshots) | each FR_ role |
| 08 | [08_authentication_and_network.sql](08_authentication_and_network.sql) | Key rotation, network rules, auth policies (read first!) | SECURITYADMIN |
| — | [data_contracts.md](data_contracts.md) | A real contract for the POS feed and where each clause is enforced | — |

---

## 1. Concepts in plain language

### RBAC in two layers

```
users ──► FUNCTIONAL roles (FR_ANALYST, FR_MARKETING …)   = "who you are / your team"
              └──► ACCESS roles (AR_MARTS_SALES_READ …)   = "what you can touch"
                        └──► privileges on objects (USAGE, SELECT, future grants)
all custom roles ──► SYSADMIN (so admins can manage what they own)
```

Why two layers: when a new team appears you compose existing access roles instead of re-granting hundreds of objects;
an audit of "who can read SALES" is one `SHOW GRANTS OF ROLE AR_MARTS_SALES_READ`.
**Future grants** cover tables that don't exist yet; **managed access schemas** stop object owners from granting on their own.

### Column security: masking

A **masking policy** is a function evaluated at query time: same table, different values per role. **Tag-based masking**
attaches the policy to a tag (`PII`), so any column tagged later is protected automatically. Use `IS_ROLE_IN_SESSION()`
(respects role hierarchy) over `CURRENT_ROLE()` (primary role only).

### Row security: row access policies

A boolean function per row, usually driven by a **mapping table** (role → region). One table, one rule, every tool.
Pipelines (RETAIL_ENGINEER) must be exempt or incremental MERGEs and tests would run on a subset.

### Masking vs row access vs secure views

| Need | Tool |
| --- | --- |
| Hide or partially show a column's values | Masking policy (tag-based at scale) |
| Hide whole rows by attribute (region, brand, store) | Row access policy |
| Expose a curated/aggregated subset, hide the SQL definition, share externally | Secure view |

### Quality

- **dbt tests** at build time (Stage 4) + **source freshness** + **reconciliation** against source control totals.
- **Data Metric Functions**: Snowflake-native checks on a schedule or on change, with history.
- **Data contracts** at the staging boundary: the producer's promise, enforced by tests.

### Audit

`ACCESS_HISTORY` (who read/wrote which columns, which policies applied), `TAG_REFERENCES` (where PII lives),
`POLICY_REFERENCES`, `OBJECT_DEPENDENCIES`, `LOGIN_HISTORY`. Retained 365 days.

---

## 2. Step-by-step

1. Make sure prod marts exist: `cd capstone_retail_platform\dbt_retail; dbt build --target prod`.
2. **01** in a worksheet → **Run All**. Read the output of `SHOW FUTURE GRANTS` and `SHOW GRANTS TO ROLE FR_MARKETING`.
3. **02** → Run All. Check the tag query at the end.
4. **03** → Run All.
5. **04**: set `enable_governance: true` in `dbt_project.yml`, rebuild prod, verify tags/policy survived.
6. **07**: run statement by statement, screenshot each role (this is acceptance test 4 of the final capstone).
7. **05**: DMFs. Come back after an hour (or after the next dbt run) for results.
8. **06**: audit queries (ACCOUNT_USAGE lags up to ~3 hours; do it the next day for full results).
9. Read **08** and [data_contracts.md](data_contracts.md).

## 3. Capstone 7 — "Lock it down"

- [ ] Access/functional role design implemented for analyst, data scientist, marketing, engineer (+ Qatar manager)
- [ ] Email and phone (and names, birth date) masked by tag; marketing sees clear text
- [ ] Region row access policy on `fct_sales_line`
- [ ] All PII columns tagged — and the tags survive `dbt build` (post-hook on)
- [ ] DMFs on `RETAIL_RAW.POS.SALES_LINES` and `RETAIL_MARTS.SALES.FCT_SALES_LINE`
- [ ] Reconciliation model fails `dbt build` when a store-day differs > 0.5% (built in Stage 4 — demonstrate it here with `--late-store`)
- [ ] Screenshots of what each role sees
- [ ] Audit query: who read `DIM_CUSTOMER.EMAIL` last month

## 4. Try this

- Remove `USE SECONDARY ROLES NONE` from step 07 and rerun. Why does every role suddenly see everything?
- Add `FR_ANALYST → QA` to the mapping table. No policy change, no grant change — the analyst now sees both regions. Remove it.
- Change the masking policy body with `ALTER MASKING POLICY … SET BODY ->` to show the email domain only to analysts.
- Rebuild `dim_customer` with `enable_governance: false` and check the tags. That's why the hook exists.

## 5. Interview check

<details><summary>Design RBAC for 200 users across 5 teams.</summary>

Access roles per database/schema and privilege level (read/write), owning all object grants including future grants, in
managed-access schemas. Functional roles per team (and per sensitivity tier where needed) composed from access roles. Users
get functional roles via SCIM from the IdP (Okta/Entra) — no manual user grants. Service users per system with key-pair auth.
Everything rolls up to SYSADMIN; ACCOUNTADMIN limited to 2–3 people with MFA. All defined in Terraform, reviewed in PRs.
</details>

<details><summary>Masking vs row access vs secure views?</summary>

Masking changes column values per role (PII); row access filters rows per role (regions, brands); secure views expose a
curated projection/aggregation and hide the definition (also required for sharing). Policies are enforced on the base table
for every access path; secure views only protect access that goes through them.
</details>

<details><summary>How do you prove to an auditor who saw customer PII last month?</summary>

ACCESS_HISTORY: flatten `base_objects_accessed` to the column level for DIM_CUSTOMER.EMAIL/PHONE, join QUERY_HISTORY for the
role, check `policies_referenced` to show the masking policy applied, and list the roles allowed to see clear text from the
policy definition + role grants. Retained 365 days; export it for the audit file.
</details>

<details><summary>What does a data contract protect against?</summary>

Silent breaking changes from producers (renames, reordering, unit/type changes, new enum values, feeds stopping). The contract
makes the expectations explicit and versioned; tests at the staging boundary make violations loud before bad data reaches marts.
</details>

<details><summary>Why exempt the pipeline role from the row access policy?</summary>

dbt's incremental MERGE reads the target table. Filtered rows look "missing", so the MERGE would insert duplicates or tests
would pass on a subset. Pipelines need complete data; people get filtered views of it. Same reasoning for masking: the
pipeline must move real emails into the audience table, which is then masked for everyone except marketing.
</details>

## 6. My notes
