terraform {
  required_version = ">= 1.5.7"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
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

variable "task_group" {
  type    = string
  default = "general"

  validation {
    condition     = contains(["general", "secret", "always"], var.task_group)
    error_message = "task_group must be one of: general, secret, always."
  }
}

variable "jupyter_gsa_email" {
  type    = string
  default = "gsa-jupyter-task01@gcp-sbx-edp-comn-509423.iam.gserviceaccount.com"
}

variable "gke_admin_service_account" {
  type    = string
  default = "sa-im-gke-admin@gcp-sbx-edp-gke01.iam.gserviceaccount.com"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "gke_gcp-sbx-edp-gke01_asia-northeast3_gke-sbx-edp-main-an3"
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

resource "kubernetes_namespace_v1" "task" {
  metadata {
    name = var.task_name
    labels = {
      "jupyterhub-task"  = var.task_name
      "jupyterhub-group" = var.task_group
    }
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

output "task_namespace" {
  value = kubernetes_namespace_v1.task.metadata[0].name
}

output "task_group" {
  value = var.task_group
}

output "jupyter_ksa" {
  value = kubernetes_service_account_v1.jupyter.metadata[0].name
}
