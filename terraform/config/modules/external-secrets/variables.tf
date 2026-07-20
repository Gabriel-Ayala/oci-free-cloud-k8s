variable "compartment_id" {
  type        = string
  description = "The compartment to create the resources in"
}

variable "cluster_id" {
  type        = string
  description = "OCID of the OKE cluster authorized through workload identity"

  validation {
    condition     = var.principal_type == "InstancePrincipal" || trimspace(var.cluster_id) != ""
    error_message = "cluster_id is required for the OCI workload identity policy."
  }
}

variable "principal_type" {
  type        = string
  description = "OCI authentication principal used by External Secrets"
  default     = "Workload"

  validation {
    condition     = contains(["Workload", "InstancePrincipal"], var.principal_type)
    error_message = "principal_type must be Workload or InstancePrincipal."
  }
}

variable "create_vault" {
  type        = bool
  description = "Create a software-protected OCI Vault when vault_id is empty"
  default     = false
}

variable "cluster_name" {
  type        = string
  description = "Logical cluster name used to make IAM policy names unique"
}

variable "region" {
  description = "OCI region containing the cluster and vault"
  type        = string
}

variable "vault_id" {
  type        = string
  description = "The OCID of the Vault to store the secrets in"

  validation {
    condition     = var.create_vault || trimspace(var.vault_id) != ""
    error_message = "vault_id must reference an existing OCI Vault unless create_vault is enabled."
  }
}
