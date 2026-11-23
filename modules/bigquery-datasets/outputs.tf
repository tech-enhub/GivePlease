output "dataset_ids" {
  description = "Dataset IDs, keyed by dataset ID (use these to make other resources depend on the datasets)."
  value       = { for k, d in google_bigquery_dataset.this : k => d.dataset_id }
}

output "datasets" {
  description = "Full dataset resource IDs (projects/.../datasets/...), keyed by dataset ID."
  value       = { for k, d in google_bigquery_dataset.this : k => d.id }
}

output "table_ids" {
  description = "Fully qualified table IDs (project.dataset.table), keyed by table key."
  value       = { for k, t in google_bigquery_table.this : k => "${t.project}.${t.dataset_id}.${t.table_id}" }
}
