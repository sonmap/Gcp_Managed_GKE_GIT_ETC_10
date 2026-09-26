variable "platform_project_id" {
  type    = string
  default = "gcp-sbx-edp-gke01"
}

variable "host_project_id" {
  type    = string
  default = "gcp-prod-edp-hub-vpchost"
}

variable "region" {
  type    = string
  default = "asia-northeast3"
}

variable "network_name" {
  type    = string
  default = "vpc-prod-edp-hub"
}

variable "gke_subnet_name" {
  type    = string
  default = "subnet-prod-edp-gke-an3"
}

variable "gke_pod_range_name" {
  type    = string
  default = "pods-prod-edp-gke-an3"
}

variable "control_plane_cidr" {
  type    = string
  default = "10.253.0.0/28"
}

variable "cluster_name" {
  type    = string
  default = "gke-sbx-edp-main-an3"
}

variable "artifact_repository" {
  type    = string
  default = "ar-sbx-platform"
}

variable "request_bucket_name" {
  type    = string
  default = "gcp-sbx-edp-gke01-requests"
}

variable "bundle_bucket_name" {
  type    = string
  default = "gcp-sbx-edp-gke01-bundles"
}

variable "gateway_ip_name" {
  type    = string
  default = "ip-sbx-external-gateway"
}

variable "cloudrun_subnet_name" {
  type    = string
  default = "subnet-prod-edp-run-an3"
}

variable "provisioner_release" {
  type        = string
  default     = "20260926-im-inputfix1"
  description = "Changes when a new provisioner image must create a Cloud Run revision."
}
