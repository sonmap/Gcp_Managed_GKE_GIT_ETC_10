terraform {
  required_version = ">= 1.5.7"
  required_providers { google = { source = "hashicorp/google", version = "~> 6.0" } }
}
variable "project_id" { type = string }
variable "region" { type = string
  default = "asia-northeast3" }
variable "task_name" { type = string }
variable "group_email" { type = string }
variable "dataset_id" { type = string }
variable "bucket_name" { type = string }
variable "workload_identity_pool" { type = string }
provider "google" { project = var.project_id
  region = var.region }
resource "google_service_account" "jupyter" {
  project = var.project_id
  account_id = "gsa-jupyter-${var.task_name}"
  display_name = "Jupyter ${var.task_name}"
}
resource "google_bigquery_dataset" "task" {
  project = var.project_id
  dataset_id = var.dataset_id
  location = var.region
  delete_contents_on_destroy = false
}
resource "google_bigquery_dataset_iam_member" "group_viewer" {
  project = var.project_id
  dataset_id = google_bigquery_dataset.task.dataset_id
  role = "roles/bigquery.dataViewer"
  member = "group:${var.group_email}"
}
resource "google_bigquery_dataset_iam_member" "gsa_viewer" {
  project = var.project_id
  dataset_id = google_bigquery_dataset.task.dataset_id
  role = "roles/bigquery.dataViewer"
  member = "serviceAccount:${google_service_account.jupyter.email}"
}
resource "google_storage_bucket" "task" {
  project = var.project_id
  name = var.bucket_name
  location = var.region
  uniform_bucket_level_access = true
  public_access_prevention = "enforced"
  force_destroy = false
  versioning { enabled = true }
}
resource "google_storage_bucket_iam_member" "gsa_object_user" {
  bucket = google_storage_bucket.task.name
  role = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.jupyter.email}"
}
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.jupyter.name
  role = "roles/iam.workloadIdentityUser"
  member = "serviceAccount:${var.workload_identity_pool}[${var.task_name}/ksa-jupyter-${var.task_name}]"
}
output "jupyter_gsa_email" { value = google_service_account.jupyter.email }
