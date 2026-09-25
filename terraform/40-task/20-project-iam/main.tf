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

provider "google" {
  project = var.project_id
}

resource "google_project_iam_member" "query_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "group:${var.group_email}"
}
