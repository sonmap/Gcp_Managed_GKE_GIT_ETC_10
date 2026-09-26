resource "kubernetes_namespace_v1" "gateway_system" {
  metadata {
    name = var.gateway_namespace
  }
}

resource "kubernetes_manifest" "external_http_gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.gateway_name
      namespace = kubernetes_namespace_v1.gateway_system.metadata[0].name
    }
    spec = {
      gatewayClassName = "gke-l7-global-external-managed"
      addresses = [{
        type  = "NamedAddress"
        value = var.gateway_ip_name
      }]
      listeners = [{
        name     = "http"
        protocol = "HTTP"
        port     = 80
        allowedRoutes = {
          namespaces = {
            from = "All"
          }
        }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.gateway_system]
}
