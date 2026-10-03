{#-
  Build SCD Type 2 versions from a table of change records (history is kept in RAW).
  Same logic as stage_03_modeling/02_dimensions.sql, made reusable.

    natural_key    column identifying the entity (customer_id, sku)
    changed_at     timestamp of each change record (updated_at)
    tracked_cols   columns whose change creates a new version

  Output: all input columns + attr_hash, valid_from, valid_to, is_current.
  First version starts at 1900-01-01 so facts older than our data still match;
  valid_to is EXCLUSIVE (join with >= valid_from and < valid_to).
-#}
{% macro scd2_from_changes(relation, natural_key, changed_at, tracked_cols) %}
    with hashed as (
        select
            *,
            md5(concat_ws('|',
                {%- for c in tracked_cols %}
                coalesce({{ c }}::varchar, ''){{ "," if not loop.last }}
                {%- endfor %}
            )) as attr_hash
        from {{ relation }}
    ),

    changes_only as (
        select * from hashed
        qualify lag(attr_hash) over (partition by {{ natural_key }} order by {{ changed_at }}) is distinct from attr_hash
    ),

    versions as (
        select
            *,
            iff(row_number() over (partition by {{ natural_key }} order by {{ changed_at }}) = 1,
                '1900-01-01'::timestamp_ntz, {{ changed_at }})                                   as valid_from,
            coalesce(lead({{ changed_at }}) over (partition by {{ natural_key }} order by {{ changed_at }}),
                     '9999-12-31'::timestamp_ntz)                                                as valid_to
        from changes_only
    )

    select *, valid_to = '9999-12-31'::timestamp_ntz as is_current
    from versions
{% endmacro %}
