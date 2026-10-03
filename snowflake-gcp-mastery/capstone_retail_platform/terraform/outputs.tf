output "landing_bucket_url" {
  value = module.landing_zone.landing_bucket_url
}

output "lakehouse_bucket_url" {
  value = module.landing_zone.lakehouse_bucket_url
}

output "pubsub_subscription_id" {
  value = module.landing_zone.pubsub_subscription_id
}

output "snowflake_storage_service_account" {
  description = "Google SA Snowflake uses to read GCS (granted automatically)"
  value       = local.snowflake_gcs_service_account
}

output "snowflake_pubsub_service_account" {
  description = "Google SA Snowflake uses to read Pub/Sub (granted automatically)"
  value       = snowflake_notification_integration.gcs_events.gcp_pubsub_service_account
}

output "next_steps" {
  value = <<-EOT
    Infrastructure is up. Now (repo root, venv + .env loaded):
      python capstone_retail_platform/snowflake/deploy.py --phase pre      # RAW stage, formats, tables, pipes
      python capstone_retail_platform/snowflake/deploy.py --phase backfill # reload files already in GCS
      cd capstone_retail_platform/dbt_retail
      dbt build --target prod --vars "{enable_governance: false}"         # grants for the hook don't exist yet
      cd ../..
      python capstone_retail_platform/snowflake/deploy.py --phase post     # realtime + governance (re-grants)
      cd capstone_retail_platform/dbt_retail; dbt build --target prod; cd ../..   # hook re-applies tags/policies
  EOT
}
