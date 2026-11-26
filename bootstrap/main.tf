# One-time bootstrap, run by a person (tech@enhub.ai) with local state:
#   - Terraform state bucket
#   - Workload Identity Federation for GitHub Actions (no service account keys)
#   - two CI service accounts: read-only "plan" and write "apply"

locals {
  state_bucket_name = coalesce(var.state_bucket_name, "${var.project_id}-tfstate")
  repo_owner        = split("/", var.github_repository)[0]

  bootstrap_apis = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  pool_name = google_iam_workload_identity_pool.github.name

  # Any workflow run in the repository (used for read-only plans).
  repo_principal_set = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.repository/${var.github_repository}"

  # Only jobs that run in the protected GitHub environment (used for apply).
  apply_principal = "principal://iam.googleapis.com/${local.pool_name}/subject/repo:${coalesce(var.github_oidc_subject_repo, var.github_repository)}:environment:${var.github_environment}"
  # Least-privilege roles for each CI identity on the project.
  plan_project_roles = toset([
    "roles/viewer",                            # read resources for refresh
    "roles/iam.securityReviewer",              # read IAM policies on project, buckets and datasets
    "roles/bigquery.metadataViewer",           # read dataset and table metadata
    "roles/serviceusage.serviceUsageConsumer", # needed by user_project_override
  ])

  apply_project_roles = toset([
    "roles/serviceusage.serviceUsageAdmin", # enable APIs
    "roles/serviceusage.serviceUsageConsumer",
    "roles/storage.admin",           # landing bucket and its IAM
    "roles/bigquery.admin",          # datasets, tables and dataset IAM
    "roles/iam.serviceAccountAdmin", # loader service account
  ])
}

resource "google_project_service" "bootstrap" {
  for_each = local.bootstrap_apis

  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# ---- Terraform state bucket ---------------------------------------------------

resource "google_storage_bucket" "tfstate" {
  name     = local.state_bucket_name
  project  = var.project_id
  location = upper(var.region)

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  # Keep history so a bad state write can be rolled back.
  versioning {
    enabled = true
  }

  # Keep the last 10 old versions of each state file.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
  }

  depends_on = [google_project_service.bootstrap]
}

# ---- Workload Identity Federation for GitHub Actions ---------------------------

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Short-lived credentials for GitHub Actions; no service account keys."

  depends_on = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.actor"            = "assertion.actor"
    "attribute.workflow_ref"     = "assertion.job_workflow_ref"
  }

  # Reject tokens from any other GitHub repository before any IAM check.
  attribute_condition = "assertion.repository_owner == '${local.repo_owner}' && assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ---- CI service accounts -------------------------------------------------------

resource "google_service_account" "plan" {
  project      = var.project_id
  account_id   = "tf-plan"
  display_name = "Terraform plan (GitHub Actions)"
  description  = "Read-only identity for terraform plan on pull requests."

  depends_on = [google_project_service.bootstrap]
}

resource "google_service_account" "apply" {
  project      = var.project_id
  account_id   = "tf-apply"
  display_name = "Terraform apply (GitHub Actions)"
  description  = "Write identity for terraform apply, only from the protected GitHub environment."

  depends_on = [google_project_service.bootstrap]
}

resource "google_project_iam_member" "plan" {
  for_each = local.plan_project_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.plan.member
}

resource "google_project_iam_member" "apply" {
  for_each = local.apply_project_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.apply.member
}

# The apply identity may change project IAM, but only to grant or remove
# BigQuery Job User (the loader's only project-level role).
resource "google_project_iam_member" "apply_project_iam_limited" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = google_service_account.apply.member

  condition {
    title       = "only-bigquery-job-user"
    description = "Can only grant or revoke roles/bigquery.jobUser."
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/bigquery.jobUser'])"
  }
}

# Both identities read and lock the state; plan takes a lock too.
resource "google_storage_bucket_iam_member" "state_plan" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.plan.member
}

resource "google_storage_bucket_iam_member" "state_apply" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.apply.member
}

# Which GitHub identities may impersonate which service account.
resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.repo_principal_set
}

resource "google_service_account_iam_member" "apply_wif" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.apply_principal
}
