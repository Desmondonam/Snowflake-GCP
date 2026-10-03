{#-
  Where does a model's SCHEMA go?
    prod / ci : the custom schema exactly          → RETAIL_MARTS.SALES.FCT_SALES_LINE
    dev       : <your dev schema>_<custom schema>  → RETAIL_DEV.DBT_DESMOND_SALES.FCT_SALES_LINE
  so developers never overwrite each other or production.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name in ['prod', 'ci'] -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
