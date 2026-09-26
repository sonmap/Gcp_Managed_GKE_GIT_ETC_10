resource "google_compute_network" "shared" {
  project                 = var.host_project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id
}

resource "google_compute_shared_vpc_service_project" "platform" {
  host_project    = var.host_project_id
  service_project = var.service_project_id
  depends_on      = [google_compute_shared_vpc_host_project.host]
}

resource "google_compute_subnetwork" "admin" {
  project                  = var.host_project_id
  name                     = "subnet-prod-edp-admin-an3"
  region                   = var.region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = var.admin_subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "infra_admin" {
  project                  = var.host_project_id
  name                     = "subnet-prod-edp-infra-admin-an3"
  region                   = var.region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = var.infra_admin_subnet_cidr
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "alb_frontend" {
  project                  = var.host_project_id
  name                     = "subnet-prod-edp-alb-frontend-an3"
  region                   = var.region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = var.alb_frontend_cidr
  private_ip_google_access = true
}

resource "google_compute_address" "alb" {
  project      = var.host_project_id
  name         = "ip-prod-edp-alb-an3"
  region       = var.region
  subnetwork   = google_compute_subnetwork.alb_frontend.id
  address_type = "INTERNAL"
  address      = var.alb_frontend_ip
}

resource "google_compute_subnetwork" "alb_proxy" {
  project       = var.host_project_id
  name          = "subnet-prod-edp-alb-proxy-an3"
  region        = var.region
  network       = google_compute_network.shared.id
  ip_cidr_range = var.alb_proxy_cidr
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_subnetwork" "gke" {
  project                  = var.host_project_id
  name                     = "subnet-prod-edp-gke-an3"
  region                   = var.region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = var.gke_node_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods-prod-edp-gke-an3"
    ip_cidr_range = var.gke_pod_cidr
  }
}

resource "google_compute_subnetwork" "cloudrun" {
  project                  = var.host_project_id
  name                     = "subnet-prod-edp-run-an3"
  region                   = var.region
  network                  = google_compute_network.shared.id
  ip_cidr_range            = var.cloudrun_cidr
  private_ip_google_access = true
}

resource "google_compute_global_address" "cloudbuild_psa" {
  project       = var.host_project_id
  name          = "psa-prod-edp-cloudbuild"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  network       = google_compute_network.shared.id
  address       = split("/", var.cloudbuild_psa_cidr)[0]
  prefix_length = tonumber(split("/", var.cloudbuild_psa_cidr)[1])
}

resource "google_service_networking_connection" "private_service_access" {
  network                 = google_compute_network.shared.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudbuild_psa.name]
}

# GKE Gateway firewall rules aren't created automatically in Shared VPC.
# Permit Google load balancer health checks to reach Gateway NEGs.
resource "google_compute_firewall" "gke_gateway_health_checks" {
  project     = var.host_project_id
  name        = "fw-allow-gke-gateway-health-checks"
  network     = google_compute_network.shared.name
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow Google health checks for GKE Gateway backends."

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }
}

resource "google_compute_firewall" "iap_ssh_infra_admin" {
  project     = var.host_project_id
  name        = "fw-allow-iap-ssh-infra-admin"
  network     = google_compute_network.shared.name
  direction   = "INGRESS"
  priority    = 1000
  description = "Allow IAP TCP forwarding to infra-son01 SSH."

  source_ranges = ["35.235.240.0/20"]
  target_service_accounts = [
    var.infra_vm_service_account
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
