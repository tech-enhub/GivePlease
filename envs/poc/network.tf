# Network landing zone: custom VPC in asia-southeast1 with Private Google
# Access, flow logs, deny-by-default ingress and Cloud NAT (outbound only).
# Not used by the data load itself; ready for the Cloud Run web app
# (Direct VPC egress through the serverless subnet) and Vertex AI.

module "network" {
  source = "../../modules/network"

  project_id   = var.project_id
  region       = var.region
  network_name = var.network_name

  subnets = {
    "${var.network_name}-main" = {
      ip_cidr_range = var.main_subnet_cidr
      description   = "General private workloads."
    }
    "${var.network_name}-serverless" = {
      ip_cidr_range = var.serverless_subnet_cidr
      description   = "Cloud Run Direct VPC egress."
    }
  }

  enable_nat = var.enable_nat

  depends_on = [google_project_service.required]
}
