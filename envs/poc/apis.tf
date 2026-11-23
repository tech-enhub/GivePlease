resource "google_project_service" "required" {
  for_each = local.required_apis

  project = var.project_id
  service = each.value

  # Never switch an API off when this configuration is destroyed: other
  # workloads in the project may depend on it.
  disable_on_destroy         = false
  disable_dependent_services = false
}
