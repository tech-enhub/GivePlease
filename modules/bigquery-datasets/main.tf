resource "google_bigquery_dataset" "this" {
  for_each = var.datasets

  project       = var.project_id
  dataset_id    = each.key
  friendly_name = each.value.friendly_name
  description   = each.value.description
  location      = var.location
  labels        = var.labels

  # Tables are never deleted automatically.
  default_table_expiration_ms = null
  delete_contents_on_destroy  = var.delete_contents_on_destroy
}

resource "google_bigquery_table" "this" {
  for_each = var.tables

  project     = var.project_id
  dataset_id  = google_bigquery_dataset.this[each.value.dataset_id].dataset_id
  table_id    = each.value.table_id
  description = each.value.description
  schema      = each.value.schema
  clustering  = each.value.clustering
  labels      = var.labels

  dynamic "time_partitioning" {
    for_each = each.value.partition_field == null ? [] : [each.value]

    content {
      type  = time_partitioning.value.partition_type
      field = time_partitioning.value.partition_field
    }
  }

  deletion_protection = each.value.deletion_protection
}
