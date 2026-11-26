variable "project_id" {
  description = "Project that hosts the network."
  type        = string
}

variable "region" {
  description = "Region for the subnets, Cloud Router and Cloud NAT."
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.network_name))
    error_message = "network_name must be 1-63 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "subnets" {
  description = "Subnets to create in the region, keyed by subnet name. Each gets Private Google Access and VPC flow logs."
  type = map(object({
    ip_cidr_range = string
    description   = string
  }))

  validation {
    condition     = alltrue([for s in values(var.subnets) : can(cidrhost(s.ip_cidr_range, 0))])
    error_message = "Every subnet ip_cidr_range must be a valid IPv4 CIDR, for example 10.0.0.0/24."
  }
}

variable "flow_log_sampling" {
  description = "Share of packets sampled by VPC flow logs, from 0 to 1. Lower values cost less."
  type        = number
  default     = 0.5

  validation {
    condition     = var.flow_log_sampling > 0 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling must be greater than 0 and at most 1."
  }
}

variable "flow_log_interval" {
  description = "How often flow log entries are aggregated."
  type        = string
  default     = "INTERVAL_10_MIN"

  validation {
    condition     = contains(["INTERVAL_5_SEC", "INTERVAL_30_SEC", "INTERVAL_1_MIN", "INTERVAL_5_MIN", "INTERVAL_10_MIN", "INTERVAL_15_MIN"], var.flow_log_interval)
    error_message = "flow_log_interval must be one of the INTERVAL_* values."
  }
}

variable "enable_nat" {
  description = "Create a Cloud Router and Cloud NAT so private resources can reach the internet outbound only."
  type        = bool
  default     = true
}

variable "nat_log_filter" {
  description = "Which Cloud NAT events to log: ERRORS_ONLY, TRANSLATIONS_ONLY or ALL."
  type        = string
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.nat_log_filter)
    error_message = "nat_log_filter must be ERRORS_ONLY, TRANSLATIONS_ONLY or ALL."
  }
}

variable "enable_iap_ssh" {
  description = "Allow SSH from Identity-Aware Proxy to instances tagged allow-iap-ssh. Off by default: the PoC has no VMs."
  type        = bool
  default     = false
}
