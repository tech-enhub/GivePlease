variable "project_id" {
  description = "Project that owns the service account."
  type        = string
}

variable "account_id" {
  description = "Account ID, the part of the email before @."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.account_id))
    error_message = "account_id must be 6-30 characters, start with a letter, and use lowercase letters, digits and hyphens."
  }
}

variable "display_name" {
  description = "Display name shown in the console."
  type        = string
}

variable "description" {
  description = "What the account is for."
  type        = string
  default     = null
}

variable "project_roles" {
  description = "Roles granted on the project, for example [\"roles/bigquery.jobUser\"]. Keep this list short."
  type        = set(string)
  default     = []
}

variable "bucket_roles" {
  description = "Roles granted on individual buckets, keyed by a stable name."
  type = map(object({
    bucket = string
    role   = string
  }))
  default = {}
}

variable "dataset_roles" {
  description = "Roles granted on individual BigQuery datasets, keyed by a stable name."
  type = map(object({
    dataset_id = string
    role       = string
  }))
  default = {}
}
