variable "project_id" {
  description = "ID of the existing Google Cloud project that hosts the landing zone."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 characters, lowercase letters, digits and hyphens)."
  }
}

variable "region" {
  description = "Region for every resource. GivePlease data must stay in Singapore."
  type        = string
  default     = "asia-southeast1"

  validation {
    condition     = var.region == "asia-southeast1"
    error_message = "region must be asia-southeast1 (Singapore) for the GivePlease PoC."
  }
}

variable "environment" {
  description = "Environment name, used in labels."
  type        = string
  default     = "poc"

  validation {
    condition     = contains(["poc", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: poc, dev, staging, prod."
  }
}

variable "landing_bucket_name" {
  description = "Name of the landing bucket. Defaults to <project_id>-landing. Bucket names are global and can't be changed later."
  type        = string
  default     = null

  validation {
    condition     = var.landing_bucket_name == null || can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.landing_bucket_name))
    error_message = "landing_bucket_name must be 3-63 characters: lowercase letters, digits, dots, hyphens and underscores."
  }
}

variable "landing_retention_days" {
  description = "Files in the landing bucket are deleted after this many days."
  type        = number
  default     = 30

  validation {
    condition     = var.landing_retention_days >= 1 && var.landing_retention_days <= 365
    error_message = "landing_retention_days must be between 1 and 365."
  }
}

variable "loader_service_account_id" {
  description = "Account ID (the part before @) of the loader service account."
  type        = string
  default     = "gp-loader"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.loader_service_account_id))
    error_message = "loader_service_account_id must be 6-30 characters, start with a letter, and use lowercase letters, digits and hyphens."
  }
}

variable "data_admin_group" {
  description = "Optional Google group email that gets read access to the datasets, for example data-admins@example.com. Leave null to skip."
  type        = string
  default     = null

  validation {
    condition     = var.data_admin_group == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.data_admin_group))
    error_message = "data_admin_group must be an email address or null."
  }
}

variable "labels" {
  description = "Extra labels added to every resource, on top of the standard ones."
  type        = map(string)
  default     = {}
}

# ---- Optional budget alert ---------------------------------------------------

variable "enable_budget" {
  description = "Create a monthly budget alert. Needs billing_account_id and the Billing Account Administrator or Costs Manager role on that billing account."
  type        = bool
  default     = false
}

variable "billing_account_id" {
  description = "Billing account ID linked to the project (format XXXXXX-XXXXXX-XXXXXX). Only used when enable_budget is true."
  type        = string
  default     = null

  validation {
    condition     = var.billing_account_id == null || can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account_id))
    error_message = "billing_account_id must look like 012345-6789AB-CDEF01."
  }
}

variable "budget_amount" {
  description = "Monthly budget amount, in the billing account's currency."
  type        = number
  default     = 250
}

variable "budget_currency" {
  description = "Currency code of the billing account, for example USD or SGD."
  type        = string
  default     = "USD"
}

# ---- Network ---------------------------------------------------------------------

variable "network_name" {
  description = "Name of the PoC VPC network. Subnets, router and NAT are named after it."
  type        = string
  default     = "gp-poc-vpc"
}

variable "main_subnet_cidr" {
  description = "CIDR of the main private subnet."
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition     = can(cidrhost(var.main_subnet_cidr, 0))
    error_message = "main_subnet_cidr must be a valid IPv4 CIDR."
  }
}

variable "serverless_subnet_cidr" {
  description = "CIDR of the subnet used by Cloud Run Direct VPC egress (/26 or larger)."
  type        = string
  default     = "10.0.1.0/26"

  validation {
    condition     = can(cidrhost(var.serverless_subnet_cidr, 0)) && try(tonumber(split("/", var.serverless_subnet_cidr)[1]) <= 26, false)
    error_message = "serverless_subnet_cidr must be a valid IPv4 CIDR of /26 or larger."
  }
}

variable "enable_nat" {
  description = "Create Cloud Router and Cloud NAT for outbound-only internet access."
  type        = bool
  default     = true
}
