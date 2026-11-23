resource "google_storage_bucket" "this" {
  name     = var.name
  project  = var.project_id
  location = upper(var.location)

  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy
  labels                      = var.labels

  versioning {
    enabled = var.versioning
  }

  dynamic "lifecycle_rule" {
    for_each = var.retention_days == null ? [] : [var.retention_days]

    content {
      action {
        type = "Delete"
      }
      condition {
        age = lifecycle_rule.value
      }
    }
  }
}
