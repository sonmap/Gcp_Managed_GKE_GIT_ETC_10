locals {
  jupyter_secret_ids = toset([
    "jupyter-oauth-client-id",
    "jupyter-oauth-client-secret",
    "jupyter-tls-cert",
    "jupyter-tls-key",
  ])
}

resource "google_secret_manager_secret" "jupyter" {
  for_each  = local.jupyter_secret_ids
  project   = var.platform_project_id
  secret_id = each.value

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "provisioner_accessor" {
  for_each  = google_secret_manager_secret.jupyter
  project   = var.platform_project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_service_account.provisioner.email}"
}
