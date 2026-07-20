resource "oci_kms_vault" "external_secrets" {
  count = var.create_vault ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "oke-${var.cluster_name}-secrets"
  vault_type     = "DEFAULT"
}

resource "oci_kms_key" "external_secrets" {
  count = var.create_vault ? 1 : 0

  compartment_id   = var.compartment_id
  display_name     = "oke-${var.cluster_name}-secrets-key"
  management_endpoint = oci_kms_vault.external_secrets[0].management_endpoint
  protection_mode  = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

locals {
  vault_id = var.create_vault ? oci_kms_vault.external_secrets[0].id : var.vault_id
}

resource "oci_identity_dynamic_group" "external_secrets" {
  count = var.principal_type == "InstancePrincipal" ? 1 : 0

  compartment_id = var.compartment_id
  description    = "Tools OKE worker instances used by External Secrets"
  name           = "ExternalSecrets-${var.cluster_name}"
  matching_rule  = "instance.compartment.id = '${var.compartment_id}'"
}

resource "oci_identity_policy" "external_secrets" {
  compartment_id = var.compartment_id
  description    = "Allow External Secrets to read this cluster's OCI Vault"
  name           = "ExternalSecrets-${var.cluster_name}"

  statements = var.principal_type == "Workload" ? [
    "Allow any-user to read secret-family in tenancy where all {request.principal.type = 'workload', request.principal.namespace = 'external-secrets', request.principal.service_account = 'external-secrets', request.principal.cluster_id = '${var.cluster_id}', target.vault.id = '${local.vault_id}'}"
    ] : [
    "Allow dynamic-group ExternalSecrets-${var.cluster_name} to read secret-family in tenancy where target.vault.id = '${local.vault_id}'"
  ]
}
