variable "project_id" {
  description = "Project that owns the datasets."
  type        = string
}

variable "location" {
  description = "Location for every dataset, for example asia-southeast1."
  type        = string
}

variable "datasets" {
  description = "Datasets to create, keyed by dataset ID."
  type = map(object({
    friendly_name = optional(string)
    description   = optional(string)
  }))

  validation {
    condition     = alltrue([for id in keys(var.datasets) : can(regex("^[A-Za-z0-9_]{1,1024}$", id))])
    error_message = "Dataset IDs may contain only letters, digits and underscores."
  }
}

variable "tables" {
  description = "Tables to create, keyed by a short name. dataset_id must be one of the datasets above."
  type = map(object({
    dataset_id          = string
    table_id            = string
    description         = optional(string)
    schema              = string
    partition_field     = optional(string)
    partition_type      = optional(string, "DAY")
    clustering          = optional(list(string))
    deletion_protection = optional(bool, true)
  }))
  default = {}
}

variable "delete_contents_on_destroy" {
  description = "Allow Terraform to delete datasets that still contain tables. Keep false for data."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels for datasets and tables (provider default_labels are added on top)."
  type        = map(string)
  default     = {}
}
