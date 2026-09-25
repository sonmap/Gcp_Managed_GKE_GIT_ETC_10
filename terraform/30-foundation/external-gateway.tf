locals {
  gateway_base_domain     = trimsuffix(var.gateway_dns_name, ".")
  gateway_wildcard_domain = "*.${local.gateway_base_domain}"
}

resource "google_compute_global_address" "external_gateway" {
  project      = var.platform_project_id
  name         = var.gateway_ip_name
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_dns_managed_zone" "gateway" {
  project     = var.platform_project_id
  name        = var.gateway_dns_zone_name
  dns_name    = var.gateway_dns_name
  description = "Public DNS zone for GKE namespace routes."

  dnssec_config {
    state = "on"
  }
}

resource "google_certificate_manager_dns_authorization" "gateway" {
  project = var.platform_project_id
  name    = "dns-auth-sbx-external-gateway"
  domain  = local.gateway_base_domain
  type    = "PER_PROJECT_RECORD"
}

resource "google_dns_record_set" "certificate_authorization" {
  project      = var.platform_project_id
  managed_zone = google_dns_managed_zone.gateway.name
  name         = google_certificate_manager_dns_authorization.gateway.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.gateway.dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.gateway.dns_resource_record[0].data]
}

resource "google_dns_record_set" "gateway_wildcard" {
  project      = var.platform_project_id
  managed_zone = google_dns_managed_zone.gateway.name
  name         = "*.${google_dns_managed_zone.gateway.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.external_gateway.address]
}

resource "google_certificate_manager_certificate" "gateway" {
  project = var.platform_project_id
  name    = var.gateway_certificate_name

  managed {
    domains            = [local.gateway_wildcard_domain]
    dns_authorizations = [google_certificate_manager_dns_authorization.gateway.id]
  }

  depends_on = [google_dns_record_set.certificate_authorization]
}

resource "google_certificate_manager_certificate_map" "gateway" {
  project = var.platform_project_id
  name    = var.gateway_certificate_map_name
}

resource "google_certificate_manager_certificate_map_entry" "gateway_wildcard" {
  project      = var.platform_project_id
  name         = "entry-sbx-external-gateway-wildcard"
  map          = google_certificate_manager_certificate_map.gateway.name
  hostname     = local.gateway_wildcard_domain
  certificates = [google_certificate_manager_certificate.gateway.id]
}
