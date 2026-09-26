locals {
  services = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "serviceusage.googleapis.com",
    "config.googleapis.com",
    "storage.googleapis.com"
  ])
}

resource "google_project_service" "bootstrap" {
  for_each           = local.services
  project            = var.platform_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_storage_bucket" "terraform_state" {
  name                        = var.state_bucket_name
  project                     = var.platform_project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning { enabled = true }
  public_access_prevention = "enforced"
  depends_on = [google_project_service.bootstrap]
}

resource "google_storage_bucket_iam_member" "vm_state_object_admin" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.vm_service_account}"
}

resource "google_storage_bucket_iam_member" "vm_state_bucket_reader" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${var.vm_service_account}"
}
