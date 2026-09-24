output "network_self_link" { value = google_compute_network.shared.self_link }
output "gke_subnet_self_link" { value = google_compute_subnetwork.gke.self_link }
output "gke_pod_range_name" { value = google_compute_subnetwork.gke.secondary_ip_range[0].range_name }
output "cloudrun_subnet_self_link" { value = google_compute_subnetwork.cloudrun.self_link }
output "alb_frontend_ip" { value = google_compute_address.alb.address }
