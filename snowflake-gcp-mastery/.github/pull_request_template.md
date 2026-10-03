## What and why

<!-- One or two sentences: what changes and the business reason. -->

## Checklist

- [ ] Models follow naming conventions (`stg_` / `int_` / `dim_` / `fct_` / `rpt_` / `aud_`)
- [ ] New/changed models have a description and primary-key tests; facts have `relationships` tests
- [ ] Contract columns updated in YAML if a contracted model changed
- [ ] PII columns tagged with `config: meta: {pii: …}`
- [ ] No secrets, keys or real customer data in the diff
- [ ] CI (dbt build on the zero-copy clone) is green
- [ ] Downstream impact checked (`dbt ls --select <model>+`) and consumers informed if a mart changes

## How I tested it

<!-- Commands run, row counts before/after, screenshots. -->
