terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
  }

  # Local state is fine for learning. In a team, store state in a GCS bucket:
  # backend "gcs" {
  #   bucket = "YOUR_PROJECT_ID-tfstate"
  #   prefix = "landing-zone"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
