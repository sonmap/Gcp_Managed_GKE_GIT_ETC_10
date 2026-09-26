output "cluster_name" { value = google_container_cluster.main.name }
output "artifact_repository" { value = google_artifact_registry_repository.platform.name }
output "request_bucket" { value = google_storage_bucket.requests.name }
output "bundle_bucket" { value = google_storage_bucket.bundles.name }
output "external_gateway_ip" { value = google_compute_global_address.external_gateway.address }
output "task01_hosts_entry" { value = "${google_compute_global_address.external_gateway.address} jupyter-task01.test" }
