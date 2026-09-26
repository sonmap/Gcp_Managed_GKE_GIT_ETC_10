variable "platform_project_id" {
  type    = string
  default = "gcp-sbx-edp-gke01"
}

variable "host_project_id" {
  type    = string
  default = "gcp-prod-edp-hub-vpchost"
}

variable "data_project_id" {
  type    = string
  default = "gcp-sbx-edp-comn-509423"
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "vm_service_account" {
  type    = string
  default = "620081195575-compute@developer.gserviceaccount.com"
}

variable "sandbox_folder_id" {
  type    = string
  default = "154455658682"
}

variable "billing_account_id" {
  type    = string
  default = "019BE7-53DD39-AF5098"
}

variable "gke_subnet_name" {
  type    = string
  default = "subnet-prod-edp-gke-an3"
}

variable "cloudrun_subnet_name" {
  type    = string
  default = "subnet-prod-edp-run-an3"
}

variable "alb_frontend_subnet_name" {
  type    = string
  default = "subnet-prod-edp-alb-frontend-an3"
}

variable "source_data_project_id" {
  type        = string
  default     = "pjt-c-admin"
  description = "Existing project containing the source BigQuery dataset."
}

variable "source_dataset_id" {
  type        = string
  default     = "dlk_sample"
  description = "Existing BigQuery dataset shared with task Jupyter GSAs."
}
