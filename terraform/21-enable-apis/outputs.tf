output "enabled_services" {
  value = {
    for key, service in google_project_service.all :
    key => service.service
  }
}
