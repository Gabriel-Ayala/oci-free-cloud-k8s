variable "compartment_id" {
  description = "Compartment containing the OCI Vault"
  type        = string
}

variable "vault_id" {
  description = "OCI Vault OCID"
  type        = string
}

variable "vault_key_id" {
  description = "OCI Vault encryption key OCID"
  type        = string
}

variable "cluster_name" {
  description = "Environment name used in the Vault secret name"
  type        = string
}
