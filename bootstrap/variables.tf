variable "project_id" {
  description = "Project that hosts the Terraform state bucket, the Workload Identity pool and the CI service accounts."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID."
  }
}

variable "region" {
  description = "Region for the state bucket."
  type        = string
  default     = "asia-southeast1"

  validation {
    condition     = var.region == "asia-southeast1"
    error_message = "region must be asia-southeast1 (Singapore) for the GivePlease PoC."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to authenticate, as owner/name, for example my-org/giveplease-terraform."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "github_environment" {
  description = "GitHub environment whose jobs may use the apply service account. Protect it with required reviewers in GitHub."
  type        = string
  default     = "poc"
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket. Defaults to <project_id>-tfstate."
  type        = string
  default     = null
}

variable "pool_id" {
  description = "Workload Identity pool ID (4-32 characters)."
  type        = string
  default     = "github-pool"

  validation {
    condition     = can(regex("^[a-z0-9-]{4,32}$", var.pool_id))
    error_message = "pool_id must be 4-32 lowercase letters, digits or hyphens."
  }
}

variable "provider_id" {
  description = "Workload Identity pool provider ID (4-32 characters)."
  type        = string
  default     = "github-oidc"

  validation {
    condition     = can(regex("^[a-z0-9-]{4,32}$", var.provider_id))
    error_message = "provider_id must be 4-32 lowercase letters, digits or hyphens."
  }
}
