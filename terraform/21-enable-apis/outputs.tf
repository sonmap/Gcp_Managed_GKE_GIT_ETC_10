output "enabled_services" {
  value = {
    for key, service in google_project_service.all :
    key => service.service
  }
}

output "gke_service_identity" {
  value = google_project_service_identity.gke.email
}
