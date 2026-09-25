variable "platform_project_id" { 
  type = string
  default = "gcp-sbx-edp-gke01" 
}

variable "host_project_id" { 
  type = string
  default = "gcp-prod-edp-hub-vpchost" 
}

variable "data_project_id" { 
  type = string
  default = "gcp-sbx-edp-comn-509423" 
}

variable "region" { 
  type = string
  default = "asia-northeast3" 
}

variable "vm_service_account" { 
  type = string
  default = "40744085720-compute@developer.gserviceaccount.com" 
}

variable "gke_subnet_name" { 
  type = string
  default = "subnet-prod-edp-gke-an3" 
}

variable "cloudrun_subnet_name" { 
  type = string
  default = "subnet-prod-edp-run-an3" 
}

variable "alb_frontend_subnet_name" { 
  type = string
  default = "subnet-prod-edp-alb-frontend-an3" 
}
