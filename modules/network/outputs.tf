output "network_id" {
  description = "VPC network resource ID."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "VPC network self link."
  value       = google_compute_network.this.self_link
}

output "subnets" {
  description = "Subnets keyed by name: ID, self link and CIDR range."
  value = {
    for k, s in google_compute_subnetwork.this : k => {
      id            = s.id
      self_link     = s.self_link
      ip_cidr_range = s.ip_cidr_range
    }
  }
}

output "router_name" {
  description = "Cloud Router name, or null when NAT is off."
  value       = var.enable_nat ? google_compute_router.this[0].name : null
}

output "nat_name" {
  description = "Cloud NAT name, or null when NAT is off."
  value       = var.enable_nat ? google_compute_router_nat.this[0].name : null
}
