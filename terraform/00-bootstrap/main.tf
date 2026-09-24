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
