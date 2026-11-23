# GivePlease BigQuery PoC: data landing zone (environment: poc).
# Composes the reusable modules in ../../modules.

module "landing_bucket" {
  source = "../../modules/gcs-landing-bucket"

  project_id     = var.project_id
  name           = local.landing_bucket_name
  location       = var.region
  retention_days = var.landing_retention_days

  depends_on = [google_project_service.required]
}

module "bigquery" {
  source = "../../modules/bigquery-datasets"

  project_id = var.project_id
  location   = var.region
  datasets   = local.datasets
  tables     = local.tables

  depends_on = [google_project_service.required]
}

module "loader" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = var.loader_service_account_id
  display_name = "GivePlease PoC data loader"
  description  = "Uploads files to the landing bucket and loads them into gp_raw and gp_audit."

  # Run BigQuery load and query jobs (no data access by itself).
  project_roles = ["roles/bigquery.jobUser"]

  # Add, read and replace files in the landing bucket only.
  bucket_roles = {
    landing_object_admin = {
      bucket = module.landing_bucket.name
      role   = "roles/storage.objectAdmin"
    }
  }

  # Create tables and write rows in gp_raw and gp_audit only; no access to gp_curated.
  dataset_roles = {
    raw_data_editor = {
      dataset_id = module.bigquery.dataset_ids["gp_raw"]
      role       = "roles/bigquery.dataEditor"
    }
    audit_data_editor = {
      dataset_id = module.bigquery.dataset_ids["gp_audit"]
      role       = "roles/bigquery.dataEditor"
    }
  }

  depends_on = [google_project_service.required]
}

# Optional read access for a data-admins group -------------------------------

resource "google_bigquery_dataset_iam_member" "admin_data_viewer" {
  for_each = { for k, v in module.bigquery.dataset_ids : k => v if var.data_admin_group != null }

  project    = var.project_id
  dataset_id = each.value
  role       = "roles/bigquery.dataViewer"
  member     = "group:${var.data_admin_group}"
}

resource "google_project_iam_member" "admin_job_user" {
  count = var.data_admin_group == null ? 0 : 1

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "group:${var.data_admin_group}"
}
