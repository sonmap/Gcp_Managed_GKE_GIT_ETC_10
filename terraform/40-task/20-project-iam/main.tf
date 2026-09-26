terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" {
  type = string
}

variable "group_email" {
  type = string
}

variable "project_iam_service_account" {
  type    = string
  default = "sa-im-project-iam@gcp-sbx-edp-gke01.iam.gserviceaccount.com"
}

provider "google" {
  project                     = var.project_id
  impersonate_service_account = var.project_iam_service_account
}

resource "google_project_iam_member" "query_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "group:${var.group_email}"
}
