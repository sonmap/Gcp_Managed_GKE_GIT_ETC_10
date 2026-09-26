variable "platform_project_id" { type = string }
variable "data_project_id" { type = string }
variable "create_project" {
  type    = bool
  default = false
}
variable "project_name" { type = string }
variable "folder_id" { type = string }
variable "billing_account_id" { type = string }
variable "region" {
  type    = string
  default = "asia-northeast3"
}
variable "task_name" { type = string }
variable "group_email" { type = string }
variable "dataset_id" { type = string }
variable "source_data_project_id" { type = string }
variable "source_dataset_id" { type = string }
variable "bucket_name" { type = string }
variable "workload_identity_pool" { type = string }

variable "project_factory_service_account" {
  type    = string
  default = "sa-im-project-factory@gcp-sbx-edp-gke01.iam.gserviceaccount.com"
}
variable "project_iam_service_account" {
  type    = string
  default = "sa-im-project-iam@gcp-sbx-edp-gke01.iam.gserviceaccount.com"
}
variable "data_admin_service_account" {
  type    = string
  default = "sa-im-data-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com"
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
