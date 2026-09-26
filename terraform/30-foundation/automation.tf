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

data "google_service_account" "workflow" {
  project    = var.platform_project_id
  account_id = "sa-sbx-workflow"
}

data "google_storage_project_service_account" "gcs" {
  project = var.platform_project_id
}

data "google_project" "automation_platform" {
  project_id = var.platform_project_id
}

resource "google_cloud_run_v2_service" "provisioner" {
  count    = var.enable_automation_resources ? 1 : 0
  project  = var.platform_project_id
  name     = "run-sbx-provisioner"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false

  template {
    service_account = data.google_service_account.provisioner.email
    timeout         = "3600s"

    vpc_access {
      network_interfaces {
        network    = "projects/${var.host_project_id}/global/networks/${var.network_name}"
        subnetwork = "projects/${var.host_project_id}/regions/${var.region}/subnetworks/${var.cloudrun_subnet_name}"
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.provisioner_image
      env {
        name  = "REQUEST_BUCKET"
        value = google_storage_bucket.requests.name
      }
      env {
        name  = "PLATFORM_PROJECT_ID"
        value = var.platform_project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }
      env {
        name  = "IM_SERVICE_ACCOUNT"
        value = "sa-sbx-build@${var.platform_project_id}.iam.gserviceaccount.com"
      }
      env {
        name  = "GKE_ADMIN_SERVICE_ACCOUNT"
        value = "sa-im-gke-admin@${var.platform_project_id}.iam.gserviceaccount.com"
      }
      env {
        name  = "PROVISIONER_RELEASE"
        value = var.provisioner_release
      }
    }
  }
}

resource "google_project_iam_member" "gcs_eventarc_publisher" {
  count   = var.enable_automation_resources ? 1 : 0
  project = var.platform_project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_bucket_iam_member" "eventarc_bucket_viewer" {
  count  = var.enable_automation_resources ? 1 : 0
  bucket = google_storage_bucket.requests.name
  role   = "roles/storage.bucketViewer"
  member = "serviceAccount:service-${data.google_project.automation_platform.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
}

resource "google_cloud_run_v2_service_iam_member" "eventarc_invoker" {
  count    = var.enable_automation_resources ? 1 : 0
  project  = var.platform_project_id
  location = var.region
  name     = google_cloud_run_v2_service.provisioner[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${data.google_service_account.workflow.email}"
}

resource "google_eventarc_trigger" "approved_request" {
  count    = var.enable_automation_resources ? 1 : 0
  project  = var.platform_project_id
  name     = "trigger-sbx-approved-request"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.requests.name
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.provisioner[0].name
      region  = var.region
      path    = "/events/storage"
    }
  }

  service_account = data.google_service_account.workflow.email

  depends_on = [
    google_project_iam_member.gcs_eventarc_publisher,
    google_storage_bucket_iam_member.eventarc_bucket_viewer,
    google_cloud_run_v2_service_iam_member.eventarc_invoker
  ]
}
