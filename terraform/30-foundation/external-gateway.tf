resource "google_compute_global_address" "external_gateway" {
  project      = var.platform_project_id
  name         = var.gateway_ip_name
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}
