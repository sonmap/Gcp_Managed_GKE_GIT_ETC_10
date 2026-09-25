locals {
  project_services = {
    platform = {
      project_id = var.platform_project_id
      services = toset([
        "artifactregistry.googleapis.com",
        "cloudbuild.googleapis.com",
        "cloudresourcemanager.googleapis.com",
        "compute.googleapis.com",
        "config.googleapis.com",
        "container.googleapis.com",
        "eventarc.googleapis.com",
        "iam.googleapis.com",
        "iamcredentials.googleapis.com",
        "logging.googleapis.com",
        "monitoring.googleapis.com",
        "pubsub.googleapis.com",
        "run.googleapis.com",
        "secretmanager.googleapis.com",
        "serviceusage.googleapis.com",
        "storage.googleapis.com",
        "workflows.googleapis.com",
        "workflowexecutions.googleapis.com"
      ])
    }

    data = {
      project_id = var.data_project_id
      services = toset([
        "bigquery.googleapis.com",
        "bigquerystorage.googleapis.com",
        "cloudresourcemanager.googleapis.com",
        "iam.googleapis.com",
        "iamcredentials.googleapis.com",
        "serviceusage.googleapis.com",
        "storage.googleapis.com"
      ])
    }
  }

  service_bindings = flatten([
    for project_key, project_config in local.project_services : [
      for service in project_config.services : {
        key        = "${project_key}|${service}"
        project_id = project_config.project_id
        service    = service
      }
    ]
  ])
}

resource "google_project_service" "all" {
  for_each = {
    for binding in local.service_bindings :
    binding.key => binding
  }

  project            = each.value.project_id
  service            = each.value.service
  disable_on_destroy = false
}

resource "google_project_service_identity" "gke" {
  provider = google-beta
  project  = var.platform_project_id
  service  = "container.googleapis.com"

  depends_on = [google_project_service.all]
}
