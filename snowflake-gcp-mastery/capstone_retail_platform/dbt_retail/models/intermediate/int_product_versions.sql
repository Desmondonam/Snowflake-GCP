{{ scd2_from_changes(
    relation=ref('stg_erp__product_changes'),
    natural_key='sku',
    changed_at='updated_at',
    tracked_cols=['product_name', 'category', 'subcategory', 'brand', 'unit_cost', 'list_price']
) }}
