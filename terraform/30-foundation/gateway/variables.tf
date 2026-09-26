variable "platform_project_id" {
  type    = string
  default = "gcp-sbx-edp-gke01"
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "cluster_name" {
  type    = string
  default = "gke-sbx-edp-main-an3"
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

variable "gateway_namespace" {
  type    = string
  default = "gateway-system"
}

variable "gateway_name" {
  type    = string
  default = "external-http-gateway"
}

variable "gateway_ip_name" {
  type    = string
  default = "ip-sbx-external-gateway"
}
