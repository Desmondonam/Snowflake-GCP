# RetailOne bus matrix

Rows = business processes (each becomes one or more fact tables).
Columns = **conformed dimensions** (built once, shared by every fact that uses them).
This one page is the plan for the whole warehouse.

| Business process | Fact table | Grain | Date | Store | Product | Customer | Promotion | Campaign | Channel |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| POS + online sales | `fct_sales_line` | one line item | ✓ | ✓ | ✓ | ✓ | ✓ |  | ✓ |
| Returns | `fct_sales_line` (negative lines) | one returned line | ✓ | ✓ | ✓ | ✓ |  |  | ✓ |
| Inventory | `fct_inventory_daily` | store × product × day (periodic snapshot) | ✓ | ✓ | ✓ |  |  |  |  |
| Ad performance | `fct_ad_performance` | ad × day | ✓ |  |  |  |  | ✓ | ✓ |
| Marketing touchpoints | `fct_marketing_touchpoint` | one touch event | ✓ |  |  | ✓ |  | ✓ | ✓ |
| Attribution | `fct_attribution` | order × touchpoint × model | ✓ |  |  | ✓ |  | ✓ | ✓ |
| Online order fulfilment *(future)* | `fct_order_fulfilment` | one order (accumulating snapshot) | ✓ (×4 roles) | ✓ |  | ✓ |  |  | ✓ |

## Notes

- **Returns as negative lines** in the same fact keep "net sales = SUM(net_amount)" true everywhere. A separate
  returns fact is only worth it when returns have their own process attributes (reason codes, refund method, restocking).
- **Role-playing dates:** the future fulfilment fact would join `dim_date` four times (placed, picked, shipped, delivered).
- **Conformed `dim_customer`** across store (loyalty card) and online (email) is what unlocks customer 360, CLV and attribution.
- **Channel** is conformed between sales (store/online) and marketing (paid_search, email…) via `dim_channel.channel_group`.
