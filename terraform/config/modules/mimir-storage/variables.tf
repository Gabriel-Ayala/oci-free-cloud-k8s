variable "compartment_id" {
  type        = string
  description = "Compartment that owns the Mimir Object Storage bucket and policy"
}

variable "tenancy_id" {
  type        = string
  description = "Tenancy OCID where the dedicated Object Storage user is created"
}

variable "region" {
  type        = string
  description = "OCI region containing the Mimir bucket"
}

variable "vault_id" {
  type        = string
  description = "OCI Vault OCID used to store Mimir credentials"
}

variable "vault_key_id" {
  type        = string
  description = "OCI Vault master encryption key OCID"
}

variable "bucket_name" {
  type        = string
  description = "Private Object Storage bucket used by Mimir"
  default     = "oke-mimir-metrics"
}

variable "user_name" {
  type        = string
  description = "Dedicated OCI IAM user for Mimir Object Storage access"
  default     = "oke-mimir-storage"
}

variable "user_email" {
  type        = string
  description = "Primary email required by the OCI Identity API for the Mimir user"

  validation {
    condition     = trimspace(var.user_email) != ""
    error_message = "user_email must be set for the dedicated Mimir storage user."
  }
}
