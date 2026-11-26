# Custom-mode VPC with private subnets, a deny-by-default ingress firewall and,
# optionally, Cloud NAT for outbound-only internet access. No public IPs are
# assigned to anything here.

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.network_name
  description             = "GivePlease PoC network. Managed by Terraform."
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  for_each = var.subnets

  project       = var.project_id
  name          = each.key
  description   = each.value.description
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = each.value.ip_cidr_range

  # Reach Google APIs (BigQuery, Cloud Storage, Vertex AI) without public IPs.
  private_ip_google_access = true

  log_config {
    aggregation_interval = var.flow_log_interval
    flow_sampling        = var.flow_log_sampling
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ---- Firewall -------------------------------------------------------------------
# GCP already denies ingress implicitly; this explicit rule makes the default
# visible and logs what it blocks. Egress stays allowed (implied rule).

resource "google_compute_firewall" "deny_all_ingress" {
  project     = var.project_id
  name        = "${var.network_name}-deny-all-ingress"
  description = "Deny all inbound traffic not allowed by a higher-priority rule."
  network     = google_compute_network.this.id
  direction   = "INGRESS"
  priority    = 65534

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  project     = var.project_id
  name        = "${var.network_name}-allow-iap-ssh"
  description = "SSH only through Identity-Aware Proxy, only to tagged instances."
  network     = google_compute_network.this.id
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["allow-iap-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ---- Cloud Router and Cloud NAT -----------------------------------------------------

resource "google_compute_router" "this" {
  count = var.enable_nat ? 1 : 0

  project     = var.project_id
  name        = "${var.network_name}-router"
  description = "Cloud Router for Cloud NAT."
  region      = var.region
  network     = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  count = var.enable_nat ? 1 : 0

  project = var.project_id
  name    = "${var.network_name}-nat"
  router  = google_compute_router.this[0].name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = google_compute_subnetwork.this
    content {
      name                    = subnetwork.value.id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  log_config {
    enable = true
    filter = var.nat_log_filter
  }
}
