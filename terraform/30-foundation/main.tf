data "google_compute_network" "shared" {
  project = var.host_project_id
  name    = var.network_name
}

data "google_compute_subnetwork" "gke" {
  project = var.host_project_id
  region  = var.region
  name    = var.gke_subnet_name
}

resource "google_artifact_registry_repository" "platform" {
  project       = var.platform_project_id
  location      = var.region
  repository_id = var.artifact_repository
  format        = "DOCKER"
}

resource "google_storage_bucket" "requests" {
  project                     = var.platform_project_id
  name                        = var.request_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket" "bundles" {
  project                     = var.platform_project_id
  name                        = var.bundle_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

resource "google_container_cluster" "main" {
  project             = var.platform_project_id
  name                = var.cluster_name
  location            = var.region
  network             = data.google_compute_network.shared.self_link
  subnetwork          = data.google_compute_subnetwork.gke.self_link
  enable_autopilot    = true
  deletion_protection = true

  ip_allocation_policy {
    cluster_secondary_range_name = var.gke_pod_range_name
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.admin_access_cidr
      display_name = "admin-management-subnet"
    }
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.control_plane_cidr
  }

  release_channel {
    channel = "REGULAR"
  }
}
