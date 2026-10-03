output "landing_bucket_url" {
  value = module.landing_zone.landing_bucket_url
}

output "lakehouse_bucket_url" {
  value = module.landing_zone.lakehouse_bucket_url
}

output "pubsub_subscription_id" {
  value = module.landing_zone.pubsub_subscription_id
}

output "artifact_registry_repo" {
  value = module.landing_zone.artifact_registry_repo
}

output "next_steps" {
  value = <<-EOT
    1. Build your ads image:
         gcloud builds submit ../g3_cloud_run_ads --tag ${module.landing_zone.artifact_registry_repo}/ads-extract:latest
    2. Set ads_image in terraform.tfvars to that tag and run: terraform apply
    3. Run the job once:
         gcloud run jobs execute ads-extract --region ${var.region} --wait
  EOT
}
