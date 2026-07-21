variable "compartment_id" {
  type        = string
  description = "Compartment that owns the Longhorn backup bucket and policy"
}

variable "tenancy_id" {
  type        = string
  description = "Tenancy OCID where the dedicated Object Storage user is created"
}

variable "region" {
  type        = string
  description = "OCI region containing the backup bucket"
}

variable "vault_id" {
  type        = string
  description = "OCI Vault OCID used to store the S3-compatible credentials"
}

variable "vault_key_id" {
  type        = string
  description = "OCI Vault master encryption key OCID"
}

variable "bucket_name" {
  type        = string
  description = "Private Object Storage bucket used as the Longhorn backup store"
  default     = "oke-longhorn-backups"
}

variable "user_name" {
  type        = string
  description = "Dedicated OCI IAM user for Longhorn Object Storage backups"
  default     = "oke-longhorn-backup"
}

variable "user_email" {
  type        = string
  description = "Primary email required by the OCI Identity API for the dedicated backup user"

  validation {
    condition     = trimspace(var.user_email) != ""
    error_message = "user_email must be set for the dedicated OCI backup user."
  }
}
