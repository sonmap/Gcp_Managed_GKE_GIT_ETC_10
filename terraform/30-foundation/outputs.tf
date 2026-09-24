output "cluster_name" { value = google_container_cluster.main.name }
output "artifact_repository" { value = google_artifact_registry_repository.platform.name }
output "request_bucket" { value = google_storage_bucket.requests.name }
output "bundle_bucket" { value = google_storage_bucket.bundles.name }
