output "landing_bucket" {
  description = "Landing bucket name and URL."
  value = {
    name = module.landing_bucket.name
    url  = module.landing_bucket.url
  }
}

output "datasets" {
  description = "Dataset resource IDs, keyed by dataset ID."
  value       = module.bigquery.datasets
}

output "load_log_table" {
  description = "Fully qualified ID of the load log table."
  value       = module.bigquery.table_ids["load_log"]
}

output "loader_service_account_email" {
  description = "Email of the loader service account."
  value       = module.loader.email
}

output "network" {
  description = "VPC network, subnets and NAT."
  value = {
    name    = module.network.network_name
    subnets = module.network.subnets
    nat     = module.network.nat_name
  }
}
