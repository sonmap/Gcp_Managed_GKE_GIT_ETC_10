variable "platform_project_id" {
  type    = string
  default = "gcp-sbx-edp-gke01"
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "state_bucket_name" {
  type    = string
  default = "gcp-sbx-edp-gke01-tfstate"
}

variable "vm_service_account" {
  type    = string
  default = "620081195575-compute@developer.gserviceaccount.com"
}
