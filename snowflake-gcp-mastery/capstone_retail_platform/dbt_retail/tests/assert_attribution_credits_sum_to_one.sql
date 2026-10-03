-- Every attribution model must distribute exactly 100% of each order.
select attribution_model, order_id, sum(credit) as total_credit
from {{ ref('fct_attribution') }}
group by 1, 2
having abs(sum(credit) - 1) > 0.001
