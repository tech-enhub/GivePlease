# A service account with resource-level roles. No key is created: it is used
# through impersonation. All bindings are non-authoritative (*_iam_member), so
# access granted outside Terraform is left alone.

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
}

resource "google_project_iam_member" "this" {
  for_each = var.project_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.this.member
}

resource "google_storage_bucket_iam_member" "this" {
  for_each = var.bucket_roles

  bucket = each.value.bucket
  role   = each.value.role
  member = google_service_account.this.member
}

resource "google_bigquery_dataset_iam_member" "this" {
  for_each = var.dataset_roles

  project    = var.project_id
  dataset_id = each.value.dataset_id
  role       = each.value.role
  member     = google_service_account.this.member
}
