provider "google" {
  project                     = var.billing_project_id
  billing_project             = var.billing_project_id
  user_project_override       = true
  impersonate_service_account = var.group_admin_service_account
}
