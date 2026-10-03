# Snowflake account objects — the Terraform version of stage_01 capstone_01_retail_lab_account.sql.
# Schema-level objects (RAW tables, pipes, streams, tasks, policies) are deployed by ../snowflake/deploy.py,
# and every model by dbt. Terraform owns what is slow-changing and account-wide.

# ---------------------------------------------------------------------------
# Cost guardrail
# ---------------------------------------------------------------------------
resource "snowflake_resource_monitor" "monthly" {
  provider                  = snowflake.accountadmin
  name                      = "RM_RETAIL_MONTHLY"
  credit_quota              = var.monthly_credit_quota
  notify_triggers           = [75]
  suspend_trigger           = 90
  suspend_immediate_trigger = 100
}

# ---------------------------------------------------------------------------
# Warehouses (one per workload)
# ---------------------------------------------------------------------------
locals {
  warehouses = {
    LOAD_WH      = { comment = "COPY INTO / backfills", max_clusters = 1, timeout = 3600 }
    TRANSFORM_WH = { comment = "dbt, tasks, dynamic tables", max_clusters = 1, timeout = 3600 }
    BI_WH        = { comment = "Dashboards and analysts; multi-cluster", max_clusters = 2, timeout = 600 }
    LAB_WH       = { comment = "Learning / lab work", max_clusters = 1, timeout = 3600 }
  }
}

# Created as ACCOUNTADMIN because attaching a resource monitor needs it; ownership then goes to SYSADMIN.
resource "snowflake_warehouse" "wh" {
  for_each                     = local.warehouses
  provider                     = snowflake.accountadmin
  name                         = each.key
  warehouse_size               = "XSMALL"
  auto_suspend                 = 60
  auto_resume                  = "true"
  initially_suspended          = true
  min_cluster_count            = 1
  max_cluster_count            = each.value.max_clusters
  scaling_policy               = each.value.max_clusters > 1 ? "STANDARD" : null
  statement_timeout_in_seconds = each.value.timeout
  resource_monitor             = snowflake_resource_monitor.monthly.name
  comment                      = each.value.comment
}

resource "snowflake_grant_ownership" "wh_to_sysadmin" {
  for_each            = snowflake_warehouse.wh
  provider            = snowflake.accountadmin
  account_role_name   = "SYSADMIN"
  outbound_privileges = "COPY"
  on {
    object_type = "WAREHOUSE"
    object_name = each.value.name
  }
}

# ---------------------------------------------------------------------------
# Databases (one per layer)
# ---------------------------------------------------------------------------
locals {
  databases = {
    RETAIL_RAW     = { transient = false, retention = 7, comment = "Exact copies of sources + lineage. Append-only." }
    RETAIL_STAGING = { transient = false, retention = 1, comment = "Typed, cleaned, deduplicated (dbt stg_/int_)" }
    RETAIL_MARTS   = { transient = false, retention = 7, comment = "Star schemas used by the business" }
    RETAIL_DEV     = { transient = true, retention = 1, comment = "Personal dbt development schemas" }
    RETAIL_LAB     = { transient = true, retention = 1, comment = "Experiments and performance tests" }
  }
}

resource "snowflake_database" "db" {
  for_each                    = local.databases
  provider                    = snowflake.sysadmin
  name                        = each.key
  is_transient                = each.value.transient
  data_retention_time_in_days = each.value.retention
  comment                     = each.value.comment
}

# ---------------------------------------------------------------------------
# Roles and hierarchy: SYSADMIN ← RETAIL_ADMIN ← RETAIL_ENGINEER ← RETAIL_ANALYST
# ---------------------------------------------------------------------------
resource "snowflake_account_role" "admin" {
  provider = snowflake.securityadmin
  name     = "RETAIL_ADMIN"
  comment  = "RetailOne platform owner"
}

resource "snowflake_account_role" "engineer" {
  provider = snowflake.securityadmin
  name     = "RETAIL_ENGINEER"
  comment  = "Builds and runs pipelines; owns RetailOne databases"
}

resource "snowflake_account_role" "analyst" {
  provider = snowflake.securityadmin
  name     = "RETAIL_ANALYST"
  comment  = "Reads curated marts"
}

resource "snowflake_grant_account_role" "analyst_to_engineer" {
  provider         = snowflake.securityadmin
  role_name        = snowflake_account_role.analyst.name
  parent_role_name = snowflake_account_role.engineer.name
}

resource "snowflake_grant_account_role" "engineer_to_admin" {
  provider         = snowflake.securityadmin
  role_name        = snowflake_account_role.engineer.name
  parent_role_name = snowflake_account_role.admin.name
}

resource "snowflake_grant_account_role" "admin_to_sysadmin" {
  provider         = snowflake.securityadmin
  role_name        = snowflake_account_role.admin.name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_account_role" "admin_to_me" {
  provider  = snowflake.securityadmin
  role_name = snowflake_account_role.admin.name
  user_name = var.snowflake_user
}

# ---------------------------------------------------------------------------
# Ownership and privileges
# ---------------------------------------------------------------------------
resource "snowflake_grant_ownership" "db_to_engineer" {
  for_each            = snowflake_database.db
  provider            = snowflake.securityadmin
  account_role_name   = snowflake_account_role.engineer.name
  outbound_privileges = "COPY"
  on {
    object_type = "DATABASE"
    object_name = each.value.name
  }
  depends_on = [snowflake_grant_account_role.engineer_to_admin, snowflake_grant_account_role.admin_to_sysadmin]
}

resource "snowflake_grant_privileges_to_account_role" "engineer_warehouses" {
  for_each          = { for k, v in snowflake_warehouse.wh : k => v if k != "BI_WH" }
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["USAGE", "OPERATE", "MONITOR"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = each.value.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_bi_wh" {
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.wh["BI_WH"].name
  }
}

resource "snowflake_grant_privileges_to_account_role" "analyst_marts_usage" {
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.analyst.name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.db["RETAIL_MARTS"].name
  }
}

resource "snowflake_grant_privileges_to_account_role" "engineer_account" {
  provider          = snowflake.accountadmin
  account_role_name = snowflake_account_role.engineer.name
  privileges        = ["EXECUTE TASK", "EXECUTE MANAGED TASK", "CREATE DATABASE"]
  on_account        = true
}

# ---------------------------------------------------------------------------
# Service user for dbt prod / Airflow / CI (key-pair only)
# ---------------------------------------------------------------------------
resource "snowflake_service_user" "pipeline" {
  provider          = snowflake.securityadmin
  name              = "SVC_RETAIL_PIPELINE"
  default_role      = snowflake_account_role.engineer.name
  default_warehouse = snowflake_warehouse.wh["TRANSFORM_WH"].name
  rsa_public_key    = var.pipeline_public_key
  comment           = "dbt prod runs, Airflow, CI. Key-pair auth only."
}

resource "snowflake_grant_account_role" "engineer_to_pipeline" {
  provider  = snowflake.securityadmin
  role_name = snowflake_account_role.engineer.name
  user_name = snowflake_service_user.pipeline.name
}
