output "vault_id" {
  value = local.vault_id
}

output "key_id" {
  value = var.create_vault ? oci_kms_key.external_secrets[0].id : ""
}
