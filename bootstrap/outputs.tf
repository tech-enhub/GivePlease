# Copy these into the GitHub repository variables (Settings > Secrets and variables > Actions > Variables).

output "github_variables" {
  description = "Values for the GitHub Actions repository variables."
  value = {
    GCP_PROJECT_ID   = var.project_id
    GCP_WIF_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_PLAN_SA      = google_service_account.plan.email
    GCP_APPLY_SA     = google_service_account.apply.email
    TF_STATE_BUCKET  = google_storage_bucket.tfstate.name
  }
}

output "state_bucket" {
  description = "Terraform state bucket name."
  value       = google_storage_bucket.tfstate.name
}
