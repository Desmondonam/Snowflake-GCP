{#-
  Post-hook for every mart table (see dbt_project.yml). Off until Stage 7 (var enable_governance).

  Why a hook? dbt rebuilds tables with CREATE OR REPLACE, which drops column tags and policies.
  Re-applying them after every build keeps governance "in code" next to the model.

  Driven by YAML metadata:
    columns:
      - name: email
        config:
          meta: {pii: email}                    → ALTER … MODIFY COLUMN email SET TAG GOV.TAGS.PII = 'email'
    config:
      meta:
        row_access_policy: {name: GOV.POLICIES.RAP_STORE_REGION, column: store_region}
                                                → re-attaches the row access policy

  The masking policy itself is attached to the TAG once (Stage 7, tag-based masking), so tagging
  a column is all dbt needs to do.
-#}
{% macro apply_governance() %}
    {%- if not var('enable_governance', false) or not execute -%}
        {{ return('') }}
    {%- endif -%}
    {%- if model.config.materialized not in ['table', 'incremental'] -%}
        {{ return('') }}
    {%- endif -%}

    {%- set statements = [] -%}

    {%- for column in model.columns.values() -%}
        {#- meta may live under column.config.meta (dbt >= 1.10) or column.meta (older style) -#}
        {%- set col_meta = (column.config or {}).meta or column.meta or {} -%}
        {%- if col_meta.pii -%}
            {%- do statements.append(
                "alter table " ~ this ~ " modify column " ~ column.name
                ~ " set tag GOV.TAGS.PII = '" ~ col_meta.pii ~ "'"
            ) -%}
        {%- endif -%}
    {%- endfor -%}

    {%- set model_meta = model.config.meta or model.meta or {} -%}
    {%- set rap = model_meta.row_access_policy -%}
    {%- if rap -%}
        {%- do statements.append("alter table " ~ this ~ " drop all row access policies") -%}
        {%- do statements.append(
            "alter table " ~ this ~ " add row access policy " ~ rap.name ~ " on (" ~ rap.column ~ ")"
        ) -%}
    {%- endif -%}

    {{ return(statements | join(';\n')) }}
{% endmacro %}
