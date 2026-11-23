provider "google" {
  project = var.project_id
  region  = var.region

  # Bill API calls (for example the budget API) to this project, not to the
  # project of the person running Terraform.
  user_project_override = true
  billing_project       = var.project_id

  # Added to every resource that supports labels.
  default_labels = local.common_labels
}
