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

variable "region" {
  type    = string
  default = "asia-northeast3"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  services = toset([
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ])
}

resource "google_project_service" "task" {
  for_each           = local.services
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

output "project_id" {
  value = var.project_id
}
