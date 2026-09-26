terraform {
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

variable "gke_project_id" {
  type    = string
  default = "gcp-sbx-edp-gke01"
}

variable "cluster_name" {
  type    = string
  default = "gke-sbx-edp-main-an3"
}

variable "location" {
  type    = string
  default = "asia-northeast3"
}

variable "task_name" {
  type    = string
  default = "task01"
}

variable "jupyter_gsa_email" {
  type    = string
  default = "gsa-jupyter-task01@gcp-sbx-edp-comn-509423.iam.gserviceaccount.com"
}

variable "gke_admin_service_account" {
  type    = string
  default = "sa-im-gke-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com"
}

variable "gateway_namespace" {
  type    = string
  default = "gateway-system"
}

variable "gateway_name" {
  type    = string
  default = "external-http-gateway"
}

variable "gateway_hostname_suffix" {
  type    = string
  default = "test"
}

locals {
  task_hostname        = "jupyter-${var.task_name}.${trimsuffix(var.gateway_hostname_suffix, ".")}"
  backend_service_name = "web-${var.task_name}"
  app_labels = {
    app  = "task-test-web"
    task = var.task_name
  }
}

provider "google" {
  project                     = var.gke_project_id
  region                      = var.location
  impersonate_service_account = var.gke_admin_service_account
}

data "google_client_config" "current" {}

data "google_container_cluster" "main" {
  project  = var.gke_project_id
  name     = var.cluster_name
  location = var.location
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.main.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.main.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_namespace_v1" "task" {
  metadata {
    name = var.task_name
  }
}

resource "kubernetes_service_account_v1" "jupyter" {
  metadata {
    name      = "ksa-jupyter-${var.task_name}"
    namespace = kubernetes_namespace_v1.task.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = var.jupyter_gsa_email
    }
  }
}

resource "kubernetes_resource_quota_v1" "task" {
  metadata {
    name      = "quota-${var.task_name}"
    namespace = kubernetes_namespace_v1.task.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"           = "40"
      "requests.memory"        = "320Gi"
      "requests.storage"       = "3Ti"
      "persistentvolumeclaims" = "100"
    }
  }
}

resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.task.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_deployment_v1" "test_web" {
  metadata {
    name      = local.backend_service_name
    namespace = kubernetes_namespace_v1.task.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.app_labels
    }

    template {
      metadata {
        labels = local.app_labels
      }

      spec {
        service_account_name = kubernetes_service_account_v1.jupyter.metadata[0].name

        container {
          name  = "hello-app"
          image = "us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0"

          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "test_web" {
  metadata {
    name      = local.backend_service_name
    namespace = kubernetes_namespace_v1.task.metadata[0].name
  }

  spec {
    selector = local.app_labels

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_network_policy_v1" "allow_gateway_to_test_web" {
  metadata {
    name      = "allow-gateway-to-test-web"
    namespace = kubernetes_namespace_v1.task.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = local.app_labels
    }

    ingress {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_manifest" "task_route" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "route-${var.task_name}"
      namespace = kubernetes_namespace_v1.task.metadata[0].name
    }
    spec = {
      parentRefs = [{
        group       = "gateway.networking.k8s.io"
        kind        = "Gateway"
        name        = var.gateway_name
        namespace   = var.gateway_namespace
        sectionName = "http"
      }]
      hostnames = [local.task_hostname]
      rules = [{
        matches = [{
          path = {
            type  = "PathPrefix"
            value = "/"
          }
        }]
        backendRefs = [{
          group = ""
          kind  = "Service"
          name  = kubernetes_service_v1.test_web.metadata[0].name
          port  = 80
        }]
      }]
    }
  }
}

output "task_namespace" {
  value = kubernetes_namespace_v1.task.metadata[0].name
}

output "task_hostname" {
  value = local.task_hostname
}

output "gateway_parent" {
  value = "${var.gateway_namespace}/${var.gateway_name}"
}
