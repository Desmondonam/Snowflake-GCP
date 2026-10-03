# ---- GCP ------------------------------------------------------------------
variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region; must be the Snowflake account's region (us-central1)"
  type        = string
  default     = "us-central1"
}

variable "ads_image" {
  description = "Ads extractor image (see gcp/README.md G5). Default = Google's sample job image."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/job:latest"
}

# ---- Snowflake ------------------------------------------------------------
variable "snowflake_organization_name" {
  description = "First part of ORGNAME-ACCOUNTNAME"
  type        = string
}

variable "snowflake_account_name" {
  description = "Second part of ORGNAME-ACCOUNTNAME"
  type        = string
}

variable "snowflake_user" {
  description = "Your user (needs SYSADMIN, SECURITYADMIN and ACCOUNTADMIN), with key-pair auth"
  type        = string
}

variable "snowflake_private_key_path" {
  description = "Path to your encrypted .p8 private key"
  type        = string
}

variable "snowflake_private_key_passphrase" {
  description = "Passphrase of the private key"
  type        = string
  sensitive   = true
}

variable "pipeline_public_key" {
  description = "Public key body (no header/footer) for SVC_RETAIL_PIPELINE"
  type        = string
}

variable "monthly_credit_quota" {
  description = "Credits per month before warehouses are suspended"
  type        = number
  default     = 30
}
