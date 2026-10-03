variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for buckets, Cloud Run and Scheduler. Must match the Snowflake account region (us-central1)."
  type        = string
  default     = "us-central1"
}

variable "landing_bucket_name" {
  description = "Globally unique name of the landing bucket"
  type        = string
}

variable "lakehouse_bucket_name" {
  description = "Globally unique name of the lakehouse (Iceberg) bucket"
  type        = string
}

variable "force_destroy_buckets" {
  description = "Allow terraform destroy to delete buckets that still contain files. True for a lab, false in production."
  type        = bool
  default     = true
}

variable "sources" {
  description = "Source folders in the landing bucket (documented as outputs; GCS folders are just prefixes)"
  type        = list(string)
  default     = ["pos_sales", "pos_control", "ecom_orders", "crm_customers", "erp_products", "erp_stores", "erp_inventory", "ads", "web_events", "reviews"]
}

variable "ads_image" {
  description = "Container image for the ads extractor job. Default is Google's sample job image so the first apply works before you build your own."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/job:latest"
}

variable "ads_schedule" {
  description = "Cron schedule (UTC) for the ads extractor"
  type        = string
  default     = "0 3 * * *"
}

variable "labels" {
  description = "Labels applied to every resource (cost attribution)"
  type        = map(string)
  default = {
    project = "retailone"
    owner   = "data-platform"
  }
}
