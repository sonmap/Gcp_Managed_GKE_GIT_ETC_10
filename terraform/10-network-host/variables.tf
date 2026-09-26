variable "host_project_id" { 
  type = string
  default = "gcp-prod-edp-hub-vpchost" 
}

variable "service_project_id" {
  type = string
  default = "gcp-sbx-edp-gke01" 
}

variable "region" {
  type = string
  default = "asia-northeast3" 
}

variable "network_name" {
  type = string
  default = "vpc-prod-edp-hub" 
}

variable "admin_subnet_cidr" {
  type = string
  default = "172.31.10.0/24" 
}

variable "infra_admin_subnet_cidr" {
  type    = string
  default = "172.32.10.0/24"
}

variable "infra_vm_service_account" {
  type    = string
  default = "620081195575-compute@developer.gserviceaccount.com"
}

variable "alb_frontend_cidr" {
  type = string
  default = "172.31.96.0/27" 
}

variable "alb_frontend_ip" {
  type = string
  default = "172.31.96.10" 
}

variable "alb_proxy_cidr" {
  type = string
  default = "10.252.2.0/26" 
}

variable "gke_node_cidr" {
  type = string
  default = "10.252.0.0/24" 
}

variable "gke_pod_cidr" {
  type = string
  default = "10.240.0.0/20" 
}

variable "cloudrun_cidr" {
  type = string
  default = "10.251.0.0/26" 
}

variable "cloudbuild_psa_cidr" {
  type = string
  default = "10.250.0.0/24" 
}
