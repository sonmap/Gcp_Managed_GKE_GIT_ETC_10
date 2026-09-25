output "service_accounts" {
  value = {
    for key, service_account in google_service_account.automation :
    key => service_account.email
  }
}

output "vm_service_account" {
  description = "instance-son VM service account used to call Infrastructure Manager."
  value       = var.vm_service_account
}

output "vm_infrastructure_manager_role" {
  description = "Project role granted to the VM service account."
  value       = google_project_iam_member.vm_infrastructure_manager_admin.role
}

output "foundation_service_account" {
  description = "Execution service account selected by Infrastructure Manager."
  value       = google_service_account.automation["im_foundation"].email
}
