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

data "google_project" "task" {
  project_id = var.project_id
}

output "project_id" {
  value = data.google_project.task.project_id
}
