variable "billing_project_id" {
  type    = string
  default = "gcp-sbx-edp-gke01"
}

variable "group_admin_service_account" {
  type    = string
  default = "sa-sandbox-group-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com"
}

variable "customer_id" {
  type        = string
  description = "Google Workspace customer ID without the customers/ prefix."
}

variable "group_email" {
  type    = string
  default = "pgrp-gcp-sbx01@sonmap.net"
}

variable "group_display_name" {
  type    = string
  default = "GCP Sandbox 01"
}

variable "members" {
  type = set(string)
  default = [
    "user01@sonmap.net",
    "user02@sonmap.net"
  ]
}
