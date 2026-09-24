terraform {
  required_version = ">= 1.5.7"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
  }
}
variable "gke_project_id" { type = string
  default = "gcp-sbx-edp-gke01" }
variable "cluster_name" { type = string
  default = "gke-sbx-edp-main-an3" }
variable "location" { type = string
  default = "asia-northeast3" }
variable "task_name" { type = string }
variable "jupyter_gsa_email" { type = string }
data "google_client_config" "current" {}
data "google_container_cluster" "main" { project = var.gke_project_id
  name = var.cluster_name
  location = var.location }
provider "kubernetes" {
  host = "https://${data.google_container_cluster.main.endpoint}"
  token = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.main.master_auth[0].cluster_ca_certificate)
}
resource "kubernetes_namespace_v1" "task" { metadata { name = var.task_name } }
resource "kubernetes_service_account_v1" "jupyter" {
  metadata {
    name = "ksa-jupyter-${var.task_name}"
    namespace = kubernetes_namespace_v1.task.metadata[0].name
    annotations = { "iam.gke.io/gcp-service-account" = var.jupyter_gsa_email }
  }
}
resource "kubernetes_resource_quota_v1" "task" {
  metadata { name = "quota-${var.task_name}"
  namespace = kubernetes_namespace_v1.task.metadata[0].name }
  spec { hard = { "requests.cpu" = "40", "requests.memory" = "320Gi", "requests.storage" = "3Ti", "persistentvolumeclaims" = "100" } }
}
resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  metadata { name = "default-deny-ingress"
  namespace = kubernetes_namespace_v1.task.metadata[0].name }
  spec { pod_selector {}
  policy_types = ["Ingress"] }
}
