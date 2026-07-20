# output "longhorn_login" {
#   value = module.longhorn.longhorn_login
#
#   sensitive = true
# }

output "external_secrets_vault_id" {
  value = var.enable_external_secrets ? module.externalsecrets[0].vault_id : ""
}

output "external_secrets_key_id" {
  value = var.enable_external_secrets ? module.externalsecrets[0].key_id : ""
}
