terraform {
  required_version = ">= 1.5.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" { type = string }
variable "project_name" { type = string }
variable "create_project" {
  type    = bool
  default = false
}
variable "folder_id" { type = string }
variable "billing_account_id" { type = string }
variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "services" {
  type = set(string)
  default = [
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com"
  ]
}

provider "google" {
  region = var.region
}

resource "google_project" "task" {
  count               = var.create_project ? 1 : 0
  project_id          = var.project_id
  name                = var.project_name
  folder_id           = var.folder_id
  billing_account     = var.billing_account_id
  auto_create_network = false
  deletion_policy     = "PREVENT"
}

data "google_project" "task" {
  count      = var.create_project ? 0 : 1
  project_id = var.project_id
}

locals {
  effective_project_id = var.create_project ? google_project.task[0].project_id : data.google_project.task[0].project_id
}

resource "google_project_service" "task" {
  for_each = var.services
  project  = local.effective_project_id
  service  = each.value
  disable_on_destroy = false
}

output "project_id" {
  value = local.effective_project_id
}
