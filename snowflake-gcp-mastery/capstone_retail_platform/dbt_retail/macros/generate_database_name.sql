{#-
  Where does a model's DATABASE go?
    prod : the layer database                      → RETAIL_STAGING / RETAIL_MARTS
    ci   : the per-PR zero-copy clone of it         → RETAIL_MARTS_PR_42
    dev  : everything in the dev database           → RETAIL_DEV
  Sources are not affected: they always point at RETAIL_RAW.
-#}
{% macro generate_database_name(custom_database_name=none, node=none) -%}
    {%- if custom_database_name is none -%}
        {{ target.database }}
    {%- elif target.name == 'prod' -%}
        {{ custom_database_name | trim | upper }}
    {%- elif target.name == 'ci' -%}
        {{ custom_database_name | trim | upper }}_{{ env_var('DBT_CI_SUFFIX', 'LOCAL') | upper }}
    {%- else -%}
        {{ target.database }}
    {%- endif -%}
{%- endmacro %}
