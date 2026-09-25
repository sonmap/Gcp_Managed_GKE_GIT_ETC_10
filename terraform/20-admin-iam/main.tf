data "google_project" "platform" {
  project_id = var.platform_project_id
}

locals {
  default_compute_service_account = "${data.google_project.platform.number}-compute@developer.gserviceaccount.com"

  service_accounts = {
    im_foundation   = "sa-im-foundation"
    project_factory = "sa-im-project-factory"
    project_iam     = "sa-im-project-iam"
    data_admin      = "sa-im-data-admin"
    gke_admin       = "sa-im-gke-admin"
    lb_admin        = "sa-im-lb-admin"
    provisioner     = "sa-sbx-provisioner"
    build           = "sa-sbx-build"
    workflow        = "sa-sbx-workflow"
    group_admin     = "sa-sandbox-group-admin"
  }

  platform_roles = {
    im_foundation = toset([
      "roles/container.admin", "roles/run.admin", "roles/cloudbuild.builds.editor",
      "roles/artifactregistry.admin", "roles/workflows.admin", "roles/storage.admin",
      "roles/secretmanager.admin", "roles/iam.serviceAccountAdmin", "roles/serviceusage.serviceUsageAdmin",
      "roles/config.agent", "roles/compute.viewer"
    ])
    project_factory = toset(["roles/config.agent"])
    gke_admin       = toset(["roles/container.admin"])
    lb_admin  = toset(["roles/compute.loadBalancerAdmin", "roles/compute.viewer"])
    build     = toset(["roles/cloudbuild.builds.builder", "roles/config.admin", "roles/container.developer"])
    provisioner = toset(["roles/cloudbuild.builds.editor", "roles/storage.objectAdmin"])
    workflow  = toset(["roles/run.invoker"])
  }

  platform_role_bindings = flatten([
    for sa_key, roles in local.platform_roles : [
      for role in roles : { key = "${sa_key}|${role}", sa_key = sa_key, role = role }
    ]
  ])
}

resource "google_service_account" "automation" {
  for_each     = local.service_accounts
  project      = var.platform_project_id
  account_id   = each.value
  display_name = each.key
}

resource "google_project_iam_member" "platform" {
  for_each = { for item in local.platform_role_bindings : item.key => item }
  project  = var.platform_project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.automation[each.value.sa_key].email}"
}

resource "google_folder_iam_member" "project_factory_creator" {
  folder = var.sandbox_folder_id
  role   = "roles/resourcemanager.projectCreator"
  member = "serviceAccount:${google_service_account.automation["project_factory"].email}"
}

resource "google_billing_account_iam_member" "project_factory_billing_user" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.user"
  member             = "serviceAccount:${google_service_account.automation["project_factory"].email}"
}

resource "google_project_iam_member" "data_admin" {
  for_each = toset([
    "roles/bigquery.admin", "roles/storage.admin",
    "roles/iam.serviceAccountAdmin", "roles/resourcemanager.projectIamAdmin"
  ])
  project = var.data_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.automation["data_admin"].email}"
}

resource "google_project_iam_member" "project_iam_admin" {
  project = var.data_project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.automation["project_iam"].email}"
}

resource "google_project_iam_member" "foundation_host_network_viewer" {
  project = var.host_project_id
  role    = "roles/compute.networkViewer"
  member  = "serviceAccount:${google_service_account.automation["im_foundation"].email}"
}

resource "google_project_iam_member" "gke_host_service_agent_user" {
  project = var.host_project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = "serviceAccount:service-${data.google_project.platform.number}@container-engine-robot.iam.gserviceaccount.com"
}

resource "google_compute_subnetwork_iam_member" "gke_service_agents_network_user" {
  for_each = toset([
    "serviceAccount:service-${data.google_project.platform.number}@container-engine-robot.iam.gserviceaccount.com",
    "serviceAccount:${data.google_project.platform.number}@cloudservices.gserviceaccount.com"
  ])

  project    = var.host_project_id
  region     = var.region
  subnetwork = var.gke_subnet_name
  role       = "roles/compute.networkUser"
  member     = each.value
}

resource "google_compute_subnetwork_iam_member" "gke_network_user" {
  project    = var.host_project_id
  region     = var.region
  subnetwork = var.gke_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${google_service_account.automation["im_foundation"].email}"
}

resource "google_compute_subnetwork_iam_member" "run_network_user" {
  project    = var.host_project_id
  region     = var.region
  subnetwork = var.cloudrun_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${google_service_account.automation["im_foundation"].email}"
}

resource "google_compute_subnetwork_iam_member" "lb_network_user" {
  project    = var.host_project_id
  region     = var.region
  subnetwork = var.alb_frontend_subnet_name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:${google_service_account.automation["lb_admin"].email}"
}

resource "google_project_iam_member" "vm_infrastructure_manager_admin" {
  project = var.platform_project_id
  role    = "roles/config.admin"
  member  = "serviceAccount:${var.vm_service_account}"
}

resource "google_project_iam_member" "vm_operational_roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/cloudbuild.builds.viewer",
    "roles/container.clusterViewer",
    "roles/logging.viewer",
    "roles/storage.bucketViewer"
  ])

  project = var.platform_project_id
  role    = each.value
  member  = "serviceAccount:${var.vm_service_account}"
}

resource "google_service_account_iam_member" "vm_uses_foundation" {
  service_account_id = google_service_account.automation["im_foundation"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.vm_service_account}"
}

# Infrastructure Manager creates the GKE cluster and attaches the platform
# project's default Compute Engine service account to Autopilot nodes.
resource "google_service_account_iam_member" "foundation_uses_default_compute" {
  service_account_id = "projects/${var.platform_project_id}/serviceAccounts/${local.default_compute_service_account}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.automation["im_foundation"].email}"
}

resource "google_project_iam_member" "default_compute_gke_node" {
  project = var.platform_project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${local.default_compute_service_account}"
}

resource "google_service_account_iam_member" "build_uses_task_sa" {
  for_each = toset(["project_factory", "project_iam", "data_admin", "gke_admin", "lb_admin"])

  service_account_id = google_service_account.automation[each.value].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.automation["build"].email}"
}

resource "google_service_account_iam_member" "build_impersonates_task_sa" {
  for_each = toset(["project_factory", "project_iam", "data_admin", "gke_admin", "lb_admin"])
  service_account_id = google_service_account.automation[each.value].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.automation["build"].email}"
}
