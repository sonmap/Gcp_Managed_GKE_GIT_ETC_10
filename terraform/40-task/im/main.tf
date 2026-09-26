resource "google_project" "task" {
  provider = google.project_factory
  count    = var.create_project ? 1 : 0

  project_id          = var.data_project_id
  name                = var.project_name
  folder_id           = var.folder_id
  billing_account     = var.billing_account_id
  auto_create_network = false
  deletion_policy     = "PREVENT"
}

data "google_project" "task" {
  provider   = google.project_factory
  count      = var.create_project ? 0 : 1
  project_id = var.data_project_id
}

locals {
  effective_project_id = var.create_project ? google_project.task[0].project_id : data.google_project.task[0].project_id
  jupyter_account_id    = "gsa-jupyter-${var.task_name}"
}

resource "google_project_service" "task" {
  provider = google.project_factory
  for_each = var.services

  project            = local.effective_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_iam_member" "query_job_user" {
  provider = google.project_iam
  project  = local.effective_project_id
  role     = "roles/bigquery.jobUser"
  member   = "group:${var.group_email}"

  depends_on = [google_project_service.task]
}

resource "google_service_account" "jupyter" {
  provider     = google.data_admin
  project      = local.effective_project_id
  account_id   = local.jupyter_account_id
  display_name = "Jupyter ${var.task_name}"
}

resource "google_bigquery_dataset" "task" {
  provider                  = google.data_admin
  project                   = local.effective_project_id
  dataset_id                = var.dataset_id
  location                  = var.region
  delete_contents_on_destroy = false
}

resource "google_bigquery_dataset_iam_member" "group_viewer" {
  provider   = google.data_admin
  project    = local.effective_project_id
  dataset_id = google_bigquery_dataset.task.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "group:${var.group_email}"
}

resource "google_bigquery_dataset_iam_member" "gsa_viewer" {
  provider   = google.data_admin
  project    = local.effective_project_id
  dataset_id = google_bigquery_dataset.task.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.jupyter.email}"
}

resource "google_bigquery_dataset_iam_member" "source_gsa_viewer" {
  provider   = google.data_admin
  project    = var.source_data_project_id
  dataset_id = var.source_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.jupyter.email}"
}

resource "google_storage_bucket" "task" {
  provider                    = google.data_admin
  project                     = local.effective_project_id
  name                        = var.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_member" "gsa_object_user" {
  provider = google.data_admin
  bucket   = google_storage_bucket.task.name
  role     = "roles/storage.objectUser"
  member   = "serviceAccount:${google_service_account.jupyter.email}"
}

resource "google_service_account_iam_member" "workload_identity" {
  provider           = google.data_admin
  service_account_id = google_service_account.jupyter.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_identity_pool}[${var.task_name}/ksa-jupyter-${var.task_name}]"
}
