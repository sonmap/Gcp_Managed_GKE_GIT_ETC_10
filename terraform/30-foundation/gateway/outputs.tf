output "gateway" {
  value = {
    namespace = var.gateway_namespace
    name      = var.gateway_name
    ip_name   = var.gateway_ip_name
  }
}
