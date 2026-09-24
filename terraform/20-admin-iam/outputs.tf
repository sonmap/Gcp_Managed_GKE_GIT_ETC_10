output "service_accounts" { value = { for k, v in google_service_account.automation : k => v.email } }
