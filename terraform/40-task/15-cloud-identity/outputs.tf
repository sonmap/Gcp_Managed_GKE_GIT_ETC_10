output "group_email" {
  value = google_cloud_identity_group.task.group_key[0].id
}

output "members" {
  value = sort(tolist(var.members))
}
