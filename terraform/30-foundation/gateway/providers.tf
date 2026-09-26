provider "google" {
  project                     = var.platform_project_id
  region                      = var.region
  impersonate_service_account = var.gke_admin_service_account
}

data "google_client_config" "current" {}

data "google_container_cluster" "main" {
  project  = var.platform_project_id
  name     = var.cluster_name
  location = var.region
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.main.private_cluster_config[0].private_endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.main.master_auth[0].cluster_ca_certificate)
}
