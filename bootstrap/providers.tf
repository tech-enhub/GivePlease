provider "google" {
  project = var.project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    project    = "giveplease-poc"
    component  = "terraform-bootstrap"
    managed_by = "terraform"
  }
}
