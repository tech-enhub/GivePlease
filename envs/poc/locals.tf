locals {
  landing_bucket_name = coalesce(var.landing_bucket_name, "${var.project_id}-landing")

  common_labels = merge(
    {
      project     = "giveplease-poc"
      environment = var.environment
      component   = "data-landing-zone"
      managed_by  = "terraform"
    },
    var.labels,
  )

  # APIs the landing zone needs. The budget API is added only when a budget is created.
  required_apis = toset(concat(
    [
      "bigquery.googleapis.com",
      "bigquerystorage.googleapis.com",
      "storage.googleapis.com",
      "iam.googleapis.com",
      "compute.googleapis.com",
    ],
    var.enable_budget ? ["billingbudgets.googleapis.com"] : [],
  ))

  datasets = {
    gp_raw = {
      friendly_name = "GivePlease raw"
      description   = "Excel tables exactly as loaded, with agreed types and no business rules."
    }
    gp_audit = {
      friendly_name = "GivePlease audit"
      description   = "Load log and, later, KPI reference values."
    }
    gp_curated = {
      friendly_name = "GivePlease curated"
      description   = "Cleaned tables and KPI views. Created empty for later steps."
    }
  }

  tables = {
    load_log = {
      dataset_id          = "gp_audit"
      table_id            = "load_log"
      description         = "One row per table per load: row counts and load time."
      schema              = file("${path.module}/schemas/load_log.json")
      partition_field     = "loaded_at"
      deletion_protection = true
    }
  }
}
