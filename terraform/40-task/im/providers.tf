provider "google" {
  alias                       = "project_factory"
  project                     = var.platform_project_id
  region                      = var.region
  impersonate_service_account = var.project_factory_service_account
}

provider "google" {
  alias                       = "project_iam"
  project                     = var.data_project_id
  region                      = var.region
  impersonate_service_account = var.project_iam_service_account
}

provider "google" {
  alias                       = "data_admin"
  project                     = var.data_project_id
  region                      = var.region
  impersonate_service_account = var.data_admin_service_account
}
