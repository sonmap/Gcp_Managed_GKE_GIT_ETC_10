output "cluster_name" { value = google_container_cluster.main.name }
output "artifact_repository" { value = google_artifact_registry_repository.platform.name }
output "request_bucket" { value = google_storage_bucket.requests.name }
output "bundle_bucket" { value = google_storage_bucket.bundles.name }
output "external_gateway_ip" { value = google_compute_global_address.external_gateway.address }
output "external_gateway_domain" { value = "*.${trimsuffix(var.gateway_dns_name, ".")}" }
output "external_gateway_name_servers" { value = google_dns_managed_zone.gateway.name_servers }
output "external_gateway_certificate_map" { value = google_certificate_manager_certificate_map.gateway.name }
