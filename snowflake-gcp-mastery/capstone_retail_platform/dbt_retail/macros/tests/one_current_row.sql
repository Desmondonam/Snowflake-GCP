{#-
  Generic test for SCD2 dimensions: every natural key has exactly one is_current = true row.
  Usage in YAML:
    columns:
      - name: customer_id
        data_tests: [one_current_row]
-#}
{% test one_current_row(model, column_name, current_flag='is_current') %}
select {{ column_name }}, count_if({{ current_flag }}) as current_rows
from {{ model }}
group by 1
having count_if({{ current_flag }}) <> 1
{% endtest %}
