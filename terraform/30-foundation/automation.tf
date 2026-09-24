variable "enable_automation_resources" {
  type        = bool
  default     = false
  description = "Enable only after the provisioner image exists in Artifact Registry."
}

variable "provisioner_image" {
  type        = string
  default     = "asia-northeast3-docker.pkg.dev/gcp-sbx-edp-gke01/ar-sbx-platform/sandbox-provisioner:latest"
}

data "google_service_account" "provisioner" {
  project    = var.platform_project_id
  account_id = "sa-sbx-provisioner"
}

resource "google_cloud_run_v2_service" "provisioner" {
  count    = var.enable_automation_resources ? 1 : 0
  project  = var.platform_project_id
  name     = "run-sbx-provisioner"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  template {
    service_account = data.google_service_account.provisioner.email
    containers {
      image = var.provisioner_image
      env { name = "REQUEST_BUCKET"; value = google_storage_bucket.requests.name }
    }
  }
  depends_on = [google_project_service.foundation]
}
