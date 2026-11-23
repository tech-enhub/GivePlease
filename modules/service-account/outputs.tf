output "email" {
  description = "Service account email."
  value       = google_service_account.this.email
}

output "member" {
  description = "IAM member string (serviceAccount:<email>)."
  value       = google_service_account.this.member
}

output "id" {
  description = "Service account resource ID."
  value       = google_service_account.this.id
}
