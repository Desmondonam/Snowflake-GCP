terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
    snowflake = {
      source = "snowflakedb/snowflake"
      # Major versions of this provider rename attributes. If `terraform validate` reports an unknown
      # argument, open the provider docs for the installed version (registry.terraform.io/providers/snowflakedb/snowflake)
      # and adjust; the resource TYPES used here exist in 1.x and 2.x.
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# One Snowflake provider per system role: each object is created by the least powerful role that can
# create it, exactly like the SQL in Capstone 1. All aliases log in as the same user with key-pair auth.
locals {
  sf_preview_features = [
    "snowflake_storage_integration_gcs_resource",
    "snowflake_notification_integration_resource",
  ]
}

provider "snowflake" {
  alias                    = "sysadmin"
  organization_name        = var.snowflake_organization_name
  account_name             = var.snowflake_account_name
  user                     = var.snowflake_user
  authenticator            = "SNOWFLAKE_JWT"
  private_key              = file(var.snowflake_private_key_path)
  private_key_passphrase   = var.snowflake_private_key_passphrase
  role                     = "SYSADMIN"
  preview_features_enabled = local.sf_preview_features
}

provider "snowflake" {
  alias                    = "securityadmin"
  organization_name        = var.snowflake_organization_name
  account_name             = var.snowflake_account_name
  user                     = var.snowflake_user
  authenticator            = "SNOWFLAKE_JWT"
  private_key              = file(var.snowflake_private_key_path)
  private_key_passphrase   = var.snowflake_private_key_passphrase
  role                     = "SECURITYADMIN"
  preview_features_enabled = local.sf_preview_features
}

provider "snowflake" {
  alias                    = "accountadmin"
  organization_name        = var.snowflake_organization_name
  account_name             = var.snowflake_account_name
  user                     = var.snowflake_user
  authenticator            = "SNOWFLAKE_JWT"
  private_key              = file(var.snowflake_private_key_path)
  private_key_passphrase   = var.snowflake_private_key_passphrase
  role                     = "ACCOUNTADMIN"
  preview_features_enabled = local.sf_preview_features
}
