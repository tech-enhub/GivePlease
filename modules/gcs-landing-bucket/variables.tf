variable "project_id" {
  description = "Project that owns the bucket."
  type        = string
}

variable "name" {
  description = "Globally unique bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 characters: lowercase letters, digits, dots, hyphens and underscores."
  }
}

variable "location" {
  description = "Single region for the bucket, for example asia-southeast1."
  type        = string
}

variable "storage_class" {
  description = "Default storage class."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "storage_class must be STANDARD, NEARLINE, COLDLINE or ARCHIVE."
  }
}

variable "retention_days" {
  description = "Objects are deleted this many days after upload. Set to null to keep them."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days == null || (var.retention_days >= 1 && var.retention_days <= 3650)
    error_message = "retention_days must be null or between 1 and 3650."
  }
}

variable "versioning" {
  description = "Keep older versions of overwritten objects."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket while it still holds objects. Keep false for data buckets."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels for the bucket (provider default_labels are added on top)."
  type        = map(string)
  default     = {}
}
