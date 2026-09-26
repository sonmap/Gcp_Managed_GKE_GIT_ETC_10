output "project_id" { value = local.effective_project_id }
output "group_email" { value = var.group_email }
output "jupyter_gsa_email" { value = google_service_account.jupyter.email }
output "dataset_id" { value = google_bigquery_dataset.task.dataset_id }
output "bucket_name" { value = google_storage_bucket.task.name }
